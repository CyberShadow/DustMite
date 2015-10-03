int f(int i)
{
	if (i == 0)
		return 0;
	return i * i;
}

void main()
{
	assert(f(5) == 30);
}
