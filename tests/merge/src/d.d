module d;
import std.stdio;

void foo()
in
{
	writeln("Doo dee doo");
}
out
{
	writeln("Dee doo dee");
}
body
{
	writeln("Dee dee doo");
}
