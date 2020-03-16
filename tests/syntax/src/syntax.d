void main()
{
	char c1 = 'a';
	char c2 = '\n';
	string s1 = "a\n\x01\u0123\U00012345";
	// string s2 = \n; // D1 naked escape string
	string s3 = r"abc\def";
	string s4 = `ab\cd"ef`;
	/* comment 1 */
	/** comment 2 */
	/+ a /++ b +/ c */ d /* e +/
	/++ a /+ b +/ c */ d /* e +/
	#line 1
}
