import std.stdio;

void fa()
{
	total++;

	fb;
}
void fb()
{
	total++;
}
void fc()
{
	total++;

}
void fe()
{
		total++;
}
void ff()
{
		total++;
}
void fg()
{
		// output should not have {}
		total++;
}
void main()
{
	fa;
	fc;
	fe;
	ff;
	fg;

	writeln(total==7);
}
int total = 1;
