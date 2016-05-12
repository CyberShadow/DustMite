import std.stdio;

int total;

void a()
{
	total++;
}

void b(int )
{
	total++;
}

void c(){
	total++;
}

void d1(int foo)
{
	total += foo;
}

void d2(int bar)
{
	total += bar;
}

void d3(int baz)
{
	total += baz;
}

void main()
{
	a;
	b(3);
	c;

	d1(1);
	d2(1);
	d3(1);

	writeln(total==6);
}
