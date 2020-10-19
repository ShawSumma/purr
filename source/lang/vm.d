module lang.vm;

import std.stdio;
import std.range;
import std.conv;
import std.algorithm;
import std.json;
import std.traits;
import core.memory;
import core.stdc.stdlib;
import lang.srcloc;
import lang.error;
import lang.dynamic;
import lang.bytecode;
import lang.number;

alias LocalCallback = void delegate(uint index,
        Dynamic* stack, Dynamic[] locals);

enum string[2][] cmpMap()
{
    return [["oplt", "<"], ["opgt", ">"], ["oplte", "<="], ["opgte", ">="]];
}

enum string[2][] mutMap()
{
    return [["+", "add"], ["-", "sub"], ["*", "mul"], ["/", "div"], ["%", "mod"]];
}

alias allocateStackAllowed = alloca;

Span[] spans;

Dynamic run(T...)(Function func, Dynamic[] args = null, T rest = T.init)
{
    static foreach (I; T)
    {
        static assert(is(I == LocalCallback));
    }
    uint index = 0;
    Dynamic* stack = void;
    Dynamic* locals = void;
    scope (failure)
    {
        spans ~= func.spans[index];
    }
    if (func.flags & Function.Flags.isLocal)
    {
        locals = cast(Dynamic*) GC.malloc((func.stab.byPlace.length + 1 + args.length) * Dynamic.sizeof,
                0, typeid(Dynamic));
        stack = (cast(Dynamic*) allocateStackAllowed(func.stackSize * Dynamic.sizeof));
    }
    else
    {
        Dynamic* ptr = cast(Dynamic*) allocateStackAllowed(
                (func.stackSize + func.stab.byPlace.length + 1 + args.length) * Dynamic.sizeof);
        stack = ptr;
        locals = ptr + func.stackSize;
    }
    foreach (i, v; args)
    {
        locals[i] = v;
    }
    scope (success)
    {
        static foreach (callback; rest)
        {
            static if (is(typeof(callback) == LocalCallback))
            {
                {
                    Dynamic[] lo = locals[0 .. func.stab.byPlace.length + 1];
                    callback(index, stack, lo);
                }
            }
        }
    }
    Instr* instrs = func.instrs.ptr;
    whileLopp: while (true)
    {
        Instr cur = instrs[index];
        switch (cur.op)
        {
        default:
            // throw new RuntimeException("opcode not found: " ~ cur.op.to!string);
            assert(0);
        case Opcode.nop:
            break;
        case Opcode.push:
            (*(stack++)) = func.constants[cur.value];
            break;
        case Opcode.pop:
            stack--;
            break;
        case Opcode.sub:
            Function built = new Function(func.funcs[cur.value]);
            built.captured = null;
            built.parent = func;
            built.captured = new Dynamic*[built.capture.length];
            foreach (i, v; built.capture)
            {
                Function.Capture cap = built.capture[i];
                if (cap.is2)
                {
                    built.captured[i] = func.captured[cap.from];
                }
                else
                {
                    built.captured[i] = &locals[cap.from];
                }
            }
            (*(stack++)) = dynamic(built);
            break;
        case Opcode.bind:
            stack--;
            (*(stack-1)).tab[(*stack)].fun.pro = new Function(
                    (*(stack-1)).tab[(*stack)].fun.pro);
            (*(stack-1)).tab[(*stack)].fun.pro.self = [(*(stack-1))];
            (*(stack-1)) = (*(stack-1)).tab[(*stack)];
            break;
        case Opcode.call:
            stack -=cur.value;
            Dynamic f = (*(stack-1));
            switch (f.type)
            {
            case Dynamic.Type.fun:
                (*(stack-1)) = f.fun.fun(stack[0 .. 0 + cur.value]);
                break;
            case Dynamic.Type.del:
                (*(stack-1)) = (*f.fun.del)(stack[0 .. 0 + cur.value]);
                break;
            case Dynamic.Type.pro:
                (*(stack-1)) = run(f.fun.pro, stack[0 .. 0 + cur.value]);
                break;
            case Dynamic.Type.tab:
                (*(stack-1)) = f.value.tab(stack[0 .. 0 + cur.value]);
                break;
            default:
                throw new TypeException("error: not a function: " ~ f.to!string);
            }
            break;
        case Opcode.upcall:
            Dynamic* end = stack;
            stack--;
            while ((*stack).type != Dynamic.Type.end)
            {
                stack--;
            }
            Dynamic[] cargs;
            for (Dynamic* i = stack + 1; i < end; i++)
            {
                if ((*i).type == Dynamic.Type.pac)
                {
                    i++;
                    cargs ~= (*i).arr;
                }
                else
                {
                    cargs ~= (*i);
                }
            }
            Dynamic f = (*(stack-1));
            Dynamic result = void;
            switch (f.type)
            {
            case Dynamic.Type.fun:
                result = f.fun.fun(cargs);
                break;
            case Dynamic.Type.del:
                (*(stack-1)) = (*f.fun.del)(cargs);
                break;
            case Dynamic.Type.pro:
                (*(stack-1)) = run(f.fun.pro, cargs);
                break;
            case Dynamic.Type.tab:
                (*(stack-1)) = f.value.tab(cargs);
                break;
            default:
                throw new TypeException("error: not a function: " ~ f.to!string);
            }
            (*(stack-1)) = result;
            break;
        case Opcode.oplt:
            stack -=1;
            (*(stack-1)) = dynamic((*(stack-1)) < (*stack));
            break;
        case Opcode.opgt:
            stack -=1;
            (*(stack-1)) = dynamic((*(stack-1)) > (*stack));
            break;
        case Opcode.oplte:
            stack -=1;
            (*(stack-1)) = dynamic((*(stack-1)) <= (*stack));
            break;
        case Opcode.opgte:
            stack -=1;
            (*(stack-1)) = dynamic((*(stack-1)) >= (*stack));
            break;
        case Opcode.opeq:
            stack -=1;
            (*(stack-1)) = dynamic((*(stack-1)) == (*stack));
            break;
        case Opcode.opneq:
            stack -=1;
            (*(stack-1)) = dynamic((*(stack-1)) != (*stack));
            break;
        case Opcode.array:
            Dynamic* end = stack;
            stack--;
            while ((*stack).type != Dynamic.Type.end)
            {
                stack--;
            }
            Dynamic[] arr;
            for (Dynamic* i = stack + 1; i < end; i++)
            {
                if ((*i).type == Dynamic.Type.pac)
                {
                    i++;
                    arr ~= (*i).arr;
                }
                else
                {
                    arr ~= (*i);
                }
            }
            (*stack) = dynamic(arr);
            stack++;
            break;
        case Opcode.unpack:
            (*(stack++)) = dynamic(Dynamic.Type.pac);
            break;
        case Opcode.table:
            Dynamic* end = stack;
            while ((*(stack-1)).type != Dynamic.Type.end)
            {
                stack--;
            }
            Dynamic[Dynamic] table;
            for (Dynamic* i = stack; i < end; i += 2)
            {
                if ((*i).type == Dynamic.Type.pac)
                {
                    foreach (kv; (*(i + 1)).tab.byKeyValue)
                    {
                        table[kv.key] = kv.value;
                    }
                }
                else
                {
                    table[*i] = (*(i + 1));
                }
            }
            (*(stack-1)) = dynamic(table);
            break;
        case Opcode.index:
            stack--;
            Dynamic arr = (*(stack-1));
            switch (arr.type)
            {
            case Dynamic.Type.arr:
                (*(stack-1)) = (arr.arr)[(*stack).as!size_t];
                break;
            case Dynamic.Type.tab:
                (*(stack-1)) = (arr.tab)[(*stack)];
                break;
            default:
                throw new TypeException("error: cannot store at index on a " ~ arr.type.to!string);
            }
            break;
        case Opcode.opneg:
            (*(stack-1)) = -(*(stack-1));
            break;
        case Opcode.opadd:
            stack--;
            (*(stack-1)) = (*(stack-1)) + (*stack);
            break;
        case Opcode.opsub:
            stack--;
            (*(stack-1)) = (*(stack-1)) - (*stack);
            break;
        case Opcode.opmul:
            stack--;
            (*(stack-1)) = (*(stack-1)) * (*stack);
            break;
        case Opcode.opdiv:
            stack--;
            (*(stack-1)) = (*(stack-1)) / (*stack);
            break;
        case Opcode.opmod:
            stack--;
            (*(stack-1)) = (*(stack-1)) % (*stack);
            break;
        case Opcode.load:
            (*(stack++)) = locals[cur.value];
            break;
        case Opcode.loadc:
            (*(stack++)) = *func.captured[cur.value];
            break;
        case Opcode.store:
            locals[cur.value] = (*(stack-1));
            stack--;
            break;
        case Opcode.istore:
            switch ((*(stack-3)).type)
            {
            case Dynamic.Type.arr:
                (*(*(stack-3)).arrPtr)[(*(stack-2)).as!size_t] = (*(stack-1));
                break;
            case Dynamic.Type.tab:
                (*(stack-3)).tab.rawSet((*(stack-2)), (*(stack-1)));
                break;
            default:
                throw new TypeException(
                        "error: cannot store at index on a " ~ (*(stack-3)).type.to!string);
            }
            stack -=3;
            break;
        case Opcode.opstore:
        switchOpp:
            switch (func.instrs[++index].value)
            {
            default:
                assert(0);
                static foreach (opm; mutMap)
                {
            case opm[1].to!AssignOp:
                    mixin("locals[cur.value] = locals[cur.value] " ~ opm[0] ~ " (*(stack-1));");
                    break switchOpp;
                }
            }
            stack--;
            break;
        case Opcode.opistore:
        switchOpi:
            switch (func.instrs[index].value)
            {
            default:
                assert(0);
                static foreach (opm; mutMap)
                {
            case opm[1].to!AssignOp:
                    Dynamic arr = (*(stack-3));
                    switch (arr.type)
                    {
                    case Dynamic.Type.arr:
                        Array* arr2 = arr.arrPtr;
                        size_t ind = (*(stack-2)).as!size_t;
                        mixin("(*arr2)[ind] = (*arr2)[ind] " ~ opm[0] ~ " (*(stack - 1));");
                        break switchOpi;
                    case Dynamic.Type.tab:
                        mixin(
                                "arr.tab.rawSet((*(stack - 2)), arr.tab[(*(stack - 2))] "
                                ~ opm[0] ~ " (*(stack - 1)));");
                        break switchOpi;
                    default:
                        throw new TypeException(
                                "error: cannot store at index on a " ~ arr.type.to!string);
                    }
                }
            }
            stack -=3;
            break;
        case Opcode.retval:
            Dynamic v = (*(--stack));
            return v;
        case Opcode.retnone:
            return Dynamic.nil;
        case Opcode.iftrue:
            Dynamic val = (*(--stack));
            if (val.type != Dynamic.Type.nil && (val.type != Dynamic.Type.log || val.log))
            {
                index = cur.value;
            }
            break;
        case Opcode.iffalse:
            Dynamic val = (*(--stack));
            if (val.type == Dynamic.Type.nil || (val.type == Dynamic.Type.log && !val.log))
            {
                index = cur.value;
            }
            break;
        case Opcode.jump:
            index = cur.value;
            break;
        case Opcode.argno:
            (*stack) = args[cur.value];
            stack++;
            break;
        }
        index++;
    }
    assert(0);
}
