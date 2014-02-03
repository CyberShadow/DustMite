module secretmodule;

import std.stdio;

struct SecretUDA {}

@SecretUDA
void doIt()
{
	string message1 = "Hello";
	string message2 = "world";
	writeln(message1 ~ ", " ~ message2);
}
