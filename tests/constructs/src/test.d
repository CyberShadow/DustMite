import std.stdio;

void main()
{
	bool pointless; // a comment
	int total = 1;

	/////////////// WHILE ///////////////
	do
	{
		writeln("Doo dee doo");
	} while (false);

	do
		writeln("Dee doo dee");
	while (false);

	while (false)
		writeln("Doo dee doo");

	while (false)
	{
		writeln("Doo dee doo");
	}

	///////////// TRY/CATCH /////////////
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

	try
	{
		writeln("Doo dee doo");
	}
	catch(Throwable e)
	{
		writeln("Dee doo dee");
	}

	try
		writeln("Doo dee doo");
	catch(Exception e)
		writeln("Dee doo dee");
	catch(Throwable e)
		writeln("Dee doo dee");
	finally
		writeln("Dee doo dee");

	try
	{
		writeln("Doo dee doo");
	}
	catch(Exception e)
	{
		writeln("Dee doo dee");
	}
	catch(Throwable e)
	{
		writeln("Dee doo dee");
	}
	finally
	{
		writeln("Dee doo dee");
	}

	//////// FUNCTION INVARIANTS ////////

	void foo()
	in
	{
		writeln("Doo dee doo");
	}
	out
	{
		writeln("Dee doo dee");
	}
	body
	{
		writeln("Dee dee doo");
	}

	///////////// IF / ELSE /////////////

	if (false)
		writeln("Doo dee doo");
	else // a comment
		total++;
		
	if (false)
	{
		writeln("Doo dee doo");
	}
	else // a comment
		total++;

	///////////// PROMOTION /////////////

	if (true)
	{
		// output should not have {}
		total++;
	}

	writeln(total==4);
}
