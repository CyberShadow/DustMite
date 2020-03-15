import std.stdio;

import ma, mb, mc, md1, md2, md3, common;

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
