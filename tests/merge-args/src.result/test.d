int total;
void a(int , int , int )
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
void d1(int foo, int , int )
{
	total += foo;
}
void d2(int , int bar, int )
{
	total += bar;
}
void d3(int , int , int baz)
{
	total += baz;
}
import std.stdio;

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
