int f(int i)
{
	if (i == 0)
	{
		return 1;
	}
	return i * f(i - 1);
}

pragmamsg, f(5) == 120;
