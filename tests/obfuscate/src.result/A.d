module A;

import std.stdio;

struct F {}

@F
void I()
{
	string K = "Hello";
	string M = "world";
	writeln(K ~ ", " ~ M);
}
