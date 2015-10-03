int i;

void main()
{
	i = 2;
	assert(i == 2, "keepthis");
	// ...
	buggy();
	// ...
	assert(i == 2, "bugbug");
}

void buggy()
{
	// ...
	i++;
	// ...
}
