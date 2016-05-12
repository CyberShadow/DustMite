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

void d1(int foo, int bar, int baz)
{
	total += foo;
}

void d2(int foo, int bar, int baz)
{
	total += bar;
}

void d3(int foo, int bar, int baz)
{
	total += baz;
}

void main()
{
	a(1, 2, 3);
	b!(1, 2)(3);
	c!(1, 2, 3);

	d1(1, 0, 0);
	d2(0, 1, 0);
	d3(0, 0, 1);

	writeln(total==6);
}
