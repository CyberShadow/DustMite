import std.stdio;

int total;

void a()
{
	total++;
}

void b(int foo, int bar)(int )
{
	total++;
}

void c(int foo, int bar, int baz)()
{
	total++;
}

void main()
{
	a;
	b!(1, 2)(3);
	c!(1, 2, 3);

	writeln(total==3);
}
