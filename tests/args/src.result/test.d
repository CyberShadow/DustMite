import std.stdio;

int total;

void a()
{
	total++;
}

void b()(int )
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

void d2(int , int bar)
{
	total += bar;
}

void d3(int , int , int baz)
{
	total += baz;
}

void main()
{
	a;
	b!()(3);
	c;

	d1(1);
	d2(0, 1);
	d3(0, 0, 1);

	writeln(total==6);
}
