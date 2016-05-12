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

void main()
{
	a;
	b!()(3);
	c;

	writeln(total==3);
}
