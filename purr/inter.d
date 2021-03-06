module purr.inter;

import std.typecons;
import std.traits;
import std.stdio;
import std.functional;
import std.conv;
import std.algorithm;
import std.meta;
import purr.vm;
import purr.vm.bytecode;
import purr.ast.ast;
import purr.parse;
import purr.vm;
import purr.inter;
import purr.srcloc;
import purr.ast.walk;

__gshared bool dumpir = false;

void eval(SrcLoc code) {
    Node node = code.parse;
    Walker walker = new Walker;
    Bytecode func = walker.walkProgram(node);
    run(func);
}
