import x, std.stdio;

void fc()
{
	try
		writeln("Doo dee doo");
	catch(Throwable e)
		writeln("Dee doo dee");

	try
	{
		writeln("Doo dee doo");
	}
	catch(Throwable e)
		writeln("Dee doo dee");

	try
		writeln("Doo dee doo");
	catch(Throwable e)
	{
		writeln("Dee doo dee");
	}

	total++;

	try
	{
		writeln("Doo dee doo");
	}
	catch(Throwable e)
	{
		writeln("Dee doo dee");
	}
}
