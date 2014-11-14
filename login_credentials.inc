sub getLoginFor
{
	my $account = shift;
	my $handle = false;

	# add your own logins here
	if ($account eq 'wbic16')
	{
		$handle = login('', '', '', '');
	}
	elsif ($account eq 'wbic32')
	{
		$handle = login('', '', '', '');
	}

	return $handle;
}
1;
