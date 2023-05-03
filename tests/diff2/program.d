/*
 * padding
 * padding
 * padding
 * padding
 * padding
 * padding
 */

int unrelated()
{
	return 2 + 2;
}

/*
 * padding
 * padding
 * padding
 * padding
 * padding
 * padding
 */

int identifier()
{
	return 0;
}

/*
 * padding
 * padding
 * padding
 * padding
 * padding
 * padding
 */

int unrelatedCaller()
{
	return unrelated();
}

/*
 * padding
 * padding
 * padding
 * padding
 * padding
 * padding
 */

void main()
{
	pragma(msg, identifier());
}
