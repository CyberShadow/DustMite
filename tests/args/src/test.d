import std.stdio;

int total;

void a(int foo, int bar, int baz)
{
	total++;
}

void b(int foo, int bar)(int baz)
{
	total++;
}

void c(int foo, int bar, int baz)()
{
	total++;
}

void main()
{
	a(1, 2, 3);
	b!(1, 2)(3);
	c!(1, 2, 3);

	writeln(total==3);
}
