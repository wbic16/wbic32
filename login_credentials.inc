sub getLoginFor
{
	my $account = shift;
	my $handle = 0;

	if ($account eq 'wbic16')
	{
		$handle = login('b8g3HULke72BYss71TGQ',
			'M4diucU7Mkt0rHTXNJpMMYZtkPY2uvkvUWnnqzDek',
			'15250344-wDsfXCeLHNq2zVKAOivRrfgj9LtLN9TBlwx0CutxK',
			'N2cM8wsQejYJnAL4Eg0SzYlo7wWYtH6cExONFF3CFA');
	}
	elsif ($account eq 'wbic32')
	{
		$handle = login('vtic64iXMYzhNi0yNItA',
		  'LYruEgkuKYYZ72vZUTDeSsXy7SeSgfdR2TFloRWiPWk',
		  '1695604794-xNqx0urdGPBXAbQVa9M7XVXxkmtMnleE25mDdEI',
		  'JqfvcNtzOBjA5QP8TpDzDjXGFbA7UEskNU3zcGeg');
	}

	return $handle;
}
1;
