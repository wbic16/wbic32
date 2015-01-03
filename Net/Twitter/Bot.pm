#=============================================================================================================
# twitter_bot Manager
# (c) 2015 Will Bickford
# License: CC BY-SA 4.0 (http://creativecommons.org/licenses/by-sa/4.0/)
#=============================================================================================================

package Net::Twitter::Bot;
use strict;
use warnings;
use feature qw(say);
use DBI;

#my $dbfile = "willbot.db";
#my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "willbot", "willbot");

#my $query = "DROP TABLE IF EXISTS willbot";
#my $sth = $dbh->prepare($query);
#$sth->execute();

#$query = "CREATE TABLE willbot (version int)";
#$sth = $dbh->prepare($query);
#$sth->execute();

#$query = "INSERT INTO willbot (version) VALUES ('1')";
#$sth = $dbh->prepare($query);
#$sth->execute();

#$query = "SELECT version FROM willbot";
#$sth = $dbh->prepare($query);
#my $result = $sth->execute();
#my $version = 0;
#if ($result)
#{
#	my $row = $sth->fetch;
#	$version = $row->[0];
#}

#say "Willbot Version: $version";
