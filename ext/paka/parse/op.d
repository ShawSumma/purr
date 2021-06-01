module ext.paka.parse.op;

import purr.io;
import std.conv;
import purr.dynamic;
import purr.ast.ast;
import ext.paka.built;
import ext.paka.async;
import ext.paka.parse.util;

Node binaryFold(BinaryOp op, Node lhs, Node rhs)
{
    Node[] xy = [genSym, genSym];
    Node lambdaBody = op(xy[0], xy[1]);
    Form lambda = new Form("fun", new Form("args", xy), lambdaBody);
    Form domap = new Form("call", new Value(native!metaFoldBinary), [lambda, lhs, rhs]);
    return domap;
}

Node unaryFold(BinaryOp op, Node rhs)
{
    Node[] xy = [genSym, genSym];
    Node lambdaBody = op(xy[0], xy[1]);
    Form lambda = new Form("fun", new Form("args", xy), lambdaBody);
    Form domap = new Form("call", new Value(native!metaFoldUnary), [lambda, rhs]);
    return domap;
}

Node unaryDotmap(UnaryOp op, Node rhs)
{
    Node[] xy = [genSym];
    Node lambdaBody = op(xy[0]);
    Form lambda = new Form("fun", new Form("args", xy), lambdaBody);
    Form domap = new Form("call", new Value(native!metaMapPreParallel), [lambda, rhs]);
    return domap;
}

Node binaryDotmap(alias func)(BinaryOp op, Node lhs, Node rhs)
{
    Node[] xy = [genSym, genSym];
    Node lambdaBody = op(xy[0], xy[1]);
    Form lambda = new Form("fun", new Form("args", xy), lambdaBody);
    Form domap = new Form("call", new Value(native!func), [lambda, lhs, rhs]);
    return domap;
}

string[] readBinaryOp(ref string[] ops)
{
    size_t slash;
    string[] ret;
    while (ops.length >= 2)
    {
        if (ops[0] == "!")
        {
            ret ~= ops[0];
            ops = ops[1 .. $];
        }
        else if (ops[0] == "\\")
        {
            ret ~= ops[0];
            ops = ops[1 .. $];
            slash++;
        }
        else
        {
            break;
        }
    }
    ret ~= ops[0];
    ops = ops[1 .. $];
    while (ops.length != 0)
    {
        if (ops[0] == "!")
        {
            ret ~= ops[0];
            ops = ops[1 .. $];
        }
        else if (ops[0] == "\\")
        {
            if (slash == 0)
            {
                break;
            }
            ret ~= ops[0];
            ops = ops[1 .. $];
            slash--;
        }
        else
        {
            break;
        }
    }
    return ret;
}

UnaryOp parseUnaryOp(string[] ops)
{
    if (ops.length > 1)
    {
        string[] rest = ops;
        BinaryOp lastBinary = parseBinaryOp(rest.readBinaryOp);
        UnaryOp curUnary = void;
        if (rest.length != 0 && rest[0] == "\\")
        {
            ops = rest[1 .. $];
            curUnary = (Node rhs) { return unaryFold(lastBinary, rhs); };
        }
        else
        {
            curUnary = parseUnaryOp([ops[0]]);
            ops = ops[1 .. $];
        }
        while (ops.length != 0)
        {
            if (ops[0] == "!")
            {
                UnaryOp lastUnary = curUnary;
                ops = ops[1 .. $];
                curUnary = (Node rhs) { return unaryDotmap(lastUnary, rhs); };
            }
            else if (ops[0] == "\\")
            {
                throw new Exception("parse error: double unary fold is dissallowed");
            }
            else
            {
                break;
            }
        }
        if (ops.length != 0)
        {
            UnaryOp next = ops.parseUnaryOp();
            return (Node rhs) { return curUnary(next(rhs)); };
        }
        return curUnary;
    }
    string opName = ops[0];
    if (opName == "#")
    {
        return (Node rhs) { return new Form("call", new Value(native!lengthOp), [rhs]); };
    }
    else if (opName == "not")
    {
        return (Node rhs) {
            return new Form("!=", rhs, new Value(true));
        };
    }
    else if (opName == "await")
    {
        return (Node rhs) {
            return new Form("call", new Value(native!awaitOp), rhs);
        };
    }
    else if (opName == "-")
    {
        throw new Exception("parse error: not a unary operator: " ~ opName
                ~ " (consider 0- instead)");
    }
    else
    {
        throw new Exception("parse error: not a unary operator: " ~ opName);
    }
}

BinaryOp parseBinaryOp(string[] ops)
{
    if (ops.length > 1)
    {
        if (ops[0] == "!" && ops[$ - 1] == "!")
        {
            BinaryOp next = parseBinaryOp(ops[1 .. $ - 1]);
            return (Node lhs, Node rhs) {
                return binaryDotmap!metaMapBothParallel(next, lhs, rhs);
            };
        }
        if (ops[$ - 1] == "\\")
        {
            BinaryOp next = parseBinaryOp(ops[0 .. $ - 1]);
            return (Node lhs, Node rhs) { return binaryFold(next, lhs, rhs); };
        }
        if (ops[0] == "!")
        {
            BinaryOp next = parseBinaryOp(ops[1 .. $]);
            return (Node lhs, Node rhs) {
                return binaryDotmap!metaMapLhsParallel(next, lhs, rhs);
            };
        }
        if (ops[$ - 1] == "!")
        {
            BinaryOp next = parseBinaryOp(ops[0 .. $ - 1]);
            return (Node lhs, Node rhs) {
                return binaryDotmap!metaMapRhsParallel(next, lhs, rhs);
            };
        }
        assert(false);
    }
    string opName = ops[0];
    switch (opName)
    {
    case "=":
        return (Node lhs, Node rhs) {
            return new Form("set", lhs, rhs);
        };
    case "+=":
    case "~=":
    case "-=":
    case "*=":
    case "/=":
    case "%=":
        throw new Exception("no operator assignment");
    default:
        if (opName == "|>")
        {
            return (Node lhs, Node rhs) {
                return new Form("rcall", lhs, rhs);
            };
        }
        else if (opName == "thru")
        {
            return (Node lhs, Node rhs) {
                return new Form("call", new Value(native!thruOp), [lhs, rhs]);
            };
        }
        else if (opName == "to")
        {
            return (Node lhs, Node rhs) {
                return new Form("call", new Value(native!toOp), [lhs, rhs]);
            };
        }
        else if (opName == "<|")
        {
            return (Node lhs, Node rhs) {
                return new Form("call", lhs, rhs);
            };
        }
        else
        {
            if (opName == "or")
            {
                opName = "||";
            }
            else if (opName == "and")
            {
                opName = "&&";
            }
            return (Node lhs, Node rhs) {
                return new Form(opName, [lhs, rhs]);
            };
        }
    }
}
