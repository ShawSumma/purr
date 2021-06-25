module purr.ir.repr;

import core.memory;
import std.conv;
import std.array;
import std.algorithm;
import std.typecons;
import std.meta;
import purr.io;
import purr.srcloc;
import purr.inter;
import purr.ir.opt;
import purr.type.repr;

alias InstrTypes = AliasSeq!(LogicalBranch, GotoBranch,
        ReturnBranch, CallInstruction, PushInstruction, OperatorInstruction,
        LambdaInstruction, PopInstruction,
        StoreInstruction, StoreIndexInstruction, LoadInstruction);

__gshared size_t nameCount;

string genName(string prefix)()
{
    size_t ret = void;
    synchronized
    {
        ret = nameCount++;
    }
    return prefix ~ ret.to!string;
}

string indent(alias rule = x => true)(string input)
{
    string ret;
    foreach (num, line; input.splitter!(x => x == '\n').array)
    {
        if (num != 0)
        {
            ret ~= '\n';
        }
        if (rule(num))
        {
            ret ~= "    ";
        }
        ret ~= line;
    }
    return ret;
}

final class BasicBlock
{
    Span span;
    string name;
    Instruction[] instrs;
    Branch exit;
    int place = -1;

    this(string n = genName!"bb_")
    {
        name = n;
    }

    override string toString()
    {
        string ret;
        ret ~= name ~ ":\n";
        foreach (instr; instrs)
        {
            ret ~= instr.to!string;
        }
        if (exit !is null)
        {
            ret ~= exit.to!string;
        }
        return ret.indent!(x => x != 0);
    }
}

class Emittable
{
    Span span;
}

class Instruction : Emittable
{
    bool canGet(T)()
    {
        return cast(T) this !is null;
    }

    T get(T)()
    {
        assert(canGet!T, typeid(this).to!string ~ " is not a " ~ typeid(T).to!string);
        return cast(T) this;
    }
}

class Branch : Emittable
{
    BasicBlock[] target;
}

class LogicalBranch : Branch
{
    BasicBlock post;

    this(BasicBlock ift, BasicBlock iff)
    {
        target = [ift, iff];
    }

    override string toString()
    {
        string ret;
        ret ~= "branch " ~ target[0].name ~ " " ~ target[1].name ~ " \n";
        return ret;
    }
}

class GotoBranch : Branch
{
    this()
    {
        target = [];
    }

    this(BasicBlock t)
    {
        target = [t];
    }

    override string toString()
    {
        string ret;
        ret ~= "goto " ~ target[0].name ~ " \n";
        return ret;
    }
}

class ReturnBranch : Branch
{
    Type type;

    this(Type ty)
    {
        type = ty;
    }

    override string toString()
    {
        string ret;
        ret ~= "return " ~ type.to!string ~ "\n";
        return ret;
    }
}

class CallInstruction : Instruction
{
    Type func;
    Type[] args;

    this(Type f, Type[] a)
    {
        func = f;
        args = a;
    }

    override string toString()
    {
        string ret;
        ret ~= "call " ~ func.to!string ~ "\n";
        return ret;
    }
}

class PushInstruction : Instruction
{
    private void[] val;
    Type res;

    this(void[] v, Type r)
    {
        val = v;
        res = r;
    }

    this(T)(T v, Type r)
            if (is(T == bool) || is(T == double)
                || is(immutable(T) == immutable(char*)))
    {
        void[T.sizeof] arr = *cast(void[T.sizeof]*)&v;
        val = arr.dup;
        res = r;
    }

    ref void[] value()
    {
        return val;
        // if (from.fits(res))
        // {
        //     return val;
        // }
        // assert(false, res.to!string ~ " vs " ~ from.to!string);
    }

    override string toString()
    {
        string ret;
        ret ~= "push " ~ res.to!string ~ "\n";
        return ret;
    }
}
enum string[] numops = ["add", "mod", "neg", "sub", "mul", "div"];
enum string[] logicops = ["lt", "gt", "lte", "gte", "neq", "eq"];
enum string[] operators = numops ~ logicops;

class OperatorInstruction : Instruction
{
    string op;
    Type resType;
    Type[] inputTypes;

    this(string oper, Type rt, Type[] its)
    {
        op = oper;
        resType = rt;
        inputTypes = its;
        assert(operators.canFind(oper) || oper == "index" || oper == "bind");
    }

    override string toString()
    {
        string ret;
        ret ~= "operator " ~ op ~ "\n";
        return ret;
    }
}

class LambdaInstruction : Instruction
{
    BasicBlock entry;
    Type[string] types;
    string[] args;
    string impl;
    Type ret;

    this(BasicBlock bb, string[] a, Type[string] t, string ip, Type r)
    {
        entry = bb;
        types = t;
        args = a;
        impl = ip;
        ret = r;
    }

    override string toString()
    {
        string ret;
        ret ~= "lambda " ~ entry.name ~ " (" ~ types.to!string[1 .. $ - 1] ~ ")" ~ "\n";
        return ret;
    }
}

class PopInstruction : Instruction
{
    Type type;

    this(Type ty)
    {
        type = ty;
    }

    override string toString()
    {
        string ret;
        ret ~= "pop\n";
        return ret;
    }
}

class StoreInstruction : Instruction
{
    string var;
    Type type;

    this(string v, Type t)
    {
        var = v;
        type = t;
    }

    override string toString()
    {
        string ret;
        ret ~= "store " ~ var ~ ": " ~ type.to!string ~ "\n";
        return ret;
    }
}

class StoreIndexInstruction : Instruction
{
    Type type;

    this(Type t)
    {
        type = t;
    }

    override string toString()
    {
        string ret;
        ret ~= "store-index: " ~ type.to!string ~ "\n";
        return ret;
    }
}

class LoadInstruction : Instruction
{
    string var;
    Type type;

    this(string v, Type ty)
    {
        var = v;
        type = ty;
    }

    override string toString()
    {
        string ret;
        ret ~= "load " ~ var ~ ": " ~ type.to!string ~ "\n";
        return ret;
    }
}
