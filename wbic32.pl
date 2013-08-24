use Net::Twitter;
use Scalar::Util 'blessed';

my %terms;
my $best1;
my $best2;
my $best3;

my $message = 'Oh dear: I couldn\'t find wbic16 again!';

# read wbic16's timeline
my $wbic16_consumer_key = '';
my $wbic16_consumer_secret = '';
my $wbic16_token = '';
my $wbic16_token_secret = '';

my $wb = Net::Twitter->new(
    traits   => [qw/API::RESTv1_1/],
    consumer_key        => $wbic16_consumer_key,
    consumer_secret     => $wbic16_consumer_secret,
    access_token        => $wbic16_token,
    access_token_secret => $wbic16_token_secret,
);

my $statuses = $wb->home_timeline();
for my $status ( @$statuses )
{
	my $cleanString = $status->{text};
	my @tmp = split(' ', $cleanString);
	for my $t ( @tmp )
	{
		if (length($t) > 0)
		{
			if (length($t) > length($best1))
			{
				$best3 = $best2;
				$best2 = $best1;
				$best1 = $t;
			}
			if (! exists $terms{$t})
			{
				$terms{$t} = 1;
			}
			else
			{
				$terms{$t} = $terms{$t} + 1;
			}
		}
	}
}

my @unique = keys %terms;
my @top;

for my $r (@unique)
{
	$top[$terms{$r}] = $r;
}

$message = $top[0] . ' ' . $best1 . ' ' . $top[1] . ' ' . $top[2] . ' ' . $best3;
my $top_size = scalar @top;
for (my $i = 3; $i < $top_size; ++$i)
{
	$message .= ' ' . $top[$i];
}
for my $r (@unique)
{
	$message .= ' ' . $r;
}
my @cleanup = split(' ', $message);
$message = '';
for my $c (@cleanup) {
	my $temp = $message . ' ' . $c;
	if (length($temp) >= 140) {
		last;
	}
	$message = $temp;
}
$message =~ s/^\s*//g;
$message = substr $message, 0, 140;

print "\n-----------------------------------\n";
print "Message: $message\n";
print "Length: " . length($message);
print "\n-----------------------------------\n";

# post to wbic32's timeline

my $consumer_key = '';
my $consumer_secret = '';
my $token = '';
my $token_secret = '';

my $nt = Net::Twitter->new(
    traits   => [qw/API::RESTv1_1/],
    consumer_key        => $consumer_key,
    consumer_secret     => $consumer_secret,
    access_token        => $token,
    access_token_secret => $token_secret,
);

my $result = $nt->update($message);

if ( my $err = $@ )
{
	die $@ unless blessed $err && $err->isa('Net::Twitter::Error');
	warn "HTTP Response Code: ", $err->code, "\n",
			"HTTP Message......: ", $err->message, "\n",
			"Twitter error.....: ", $err->error, "\n";
}
