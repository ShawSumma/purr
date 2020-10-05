module lang.srcloc;

import std.conv;

struct Location
{
    size_t line = 1;
    size_t column = 1;
    string file;

    string pretty() {
        return line.to!string ~ ":" ~ column.to!string;
    }
}

struct Span
{
    Location first;
    Location last;

    string pretty() {
        return "from " ~ first.pretty ~ " to " ~ last.pretty;
    }
}