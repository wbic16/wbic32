use strict;
use warnings;

use Net::Twitter;
use Scalar::Util 'blessed';
use POSIX;
use File::Slurp;
use LWP::Simple;
use Config::Simple;
use File::Touch;
use JSON;
use Data::Dumper;
use feature qw(say);

require 'login_credentials.inc';

my $mode = 'Active';
my $arg = shift;
if (defined $arg)
{
	if ($arg eq 'dry-run')
	{
		$mode = 'Dry-Run';
	}
}

say "Running Mode: " . $mode;

my $config_file = 'willbot.config';
my $config = new Config::Simple($config_file);
if ($config == 0)
{
	$config = new Config::Simple(syntax=>'simple');
}
our %parms = $config->vars();
exit(Main());

sub IsActive
{
	return $mode eq 'Active';
}

sub Main
{
	my $date = strftime "%A, %B %d, %Y", localtime;

	LoadBitcoinPriceData($date);
	PostBitcoinRating($date, GetBitcoinPriceRating());
	
	$config->write($config_file);

	return 0;
}

sub LoadBitcoinPriceData
{
	our %parms;
	my $date = shift;
	my $price = $parms{'last_price'};
	my $btc_date = $parms{'last_checked'};	

	# TODO: Implement comparison to today's date
	if (! exists $parms{'last_checked'})
	{
		say "Looking up new values...";
		my $data = GetBitcoinAverageHash();
		$price = $data->{'24h_avg'};
		if (IsActive())
		{
			$btc_date = $data->{'timestamp'};
			$config->param("last_price", $price);
		}
	}
	# Hack to keep quotes
	$config->param("last_checked", "\"" . $btc_date . "\"");

	say "Last Checked: " . $btc_date;
	say "Last Price: " . $price;
}

sub GetBitcoinAverageHash
{
	my $url = "https://api.bitcoinaverage.com/ticker/USD/";
	my $content = get $url;
	return decode_json $content;
}

sub GetBitcoinAveragePrice
{
	my $key = '24h_avg';
	my $data = GetBitcoinAverageHash();
	my $price = $data->{$key};
	say "Price: $price";
	return $price;
}

sub RoundToTwoDecimals
{
	my $value = shift;
	return floor(100 * $value + 0.5) / 100;
}

sub GetBitcoinPriceRating
{
	my @hold_messages = ('Ho Ho Ho Hold!', 'HODLing like a boss', 'Just keep keep holding, just keep holding ... what do we do we HODL!');
	my $luck = int(rand(3));
	my $rating = $hold_messages[$luck];
	my $price = GetBitcoinAveragePrice();
	#my $last_price = $parms{'last_price'};
	my $last_average = $parms{'last_average'};
	my $xp = floor($price * 100 + 0.5);
	my $la = floor($last_average * 100 + 0.5);
	my $next_average = floor(($la * 29 + $xp)/30 + 0.5) / 100;
	if (IsActive())
	{
		$config->param("last_average", $next_average);
	}
	say "Average: $next_average";
	my $difference = floor(100*($next_average - $last_average) + 0.5)/100;
	say "Difference: $difference";
	my $critical = 0;
	if ($difference > 0.2) { $critical = 1; }
	if ($difference < -0.2) { $critical = 1; }
	if ($difference > 1.0) { $critical = 0.5; }
	if ($difference < -1.0) { $critical = 0.5; }
	if ($critical == 0 && $price > $next_average * 0.9) { $rating = 'Soft Sell'; }
	if ($critical == 0 && $price > $next_average * 1.11) { $rating = 'Peak Sell'; }
	if ($critical == 0.5 && $price > $next_average * 1.25) { $rating = 'Spiking Sell'; }
	if ($critical == 0.5 && $next_average * 0.75 > $price) { $rating = 'Dropping Buy'; }
	if ($critical == 0 && $next_average * 0.95 > $price) { $rating = 'Valley Buy'; }

	my $advice = $rating;
	my $baseline_rating = $rating;
	my $bcrit = 0;
	my $ecrit = 0;
	my $min_price = RoundToTwoDecimals($price * 0.95);
	my $max_price = RoundToTwoDecimals($price * 1.05);
	my $iteration = RoundToTwoDecimals(($max_price - $min_price) / 100);
	for (my $price = $min_price; $price <= $max_price; $price += $iteration)
	{
		$xp = floor($price * 100 + 0.5);
		$la = floor($last_average * 100 + 0.5);
		$next_average = floor(($la * 29 + $xp)/30 + 0.5) / 100;
		my $difference = floor(100*($next_average - $last_average) + 0.5)/100;
		my $critical = 0;
		if ($difference > 0.2) { $critical = 1; }
		if ($difference < -0.2) { $critical = 1; }
		if ($difference < 1.0 && $difference > 0.2) { $critical = 0.5; }
		if ($difference > -1.0 && $difference < -0.2) { $critical = 0.5; }

		if ($critical == 0 && $price > $next_average * 0.9) { $rating = 'Soft Sell'; }
		if ($critical == 0 && $price > $next_average * 1.11) { $rating = 'Peak Sell'; }
		if ($critical == 0.5 && $price > $next_average * 1.2) { $rating = 'Spiking Sell'; }
		if ($critical == 0.5 && $next_average * 0.75 > $price) { $rating = 'Dropping Buy'; }
		if ($critical == 0 && $next_average * 0.85 > $price) { $rating = 'Valley Buy'; }

		if ($bcrit == 0 && $critical == 0)
		{
			$bcrit = $price;
			$advice = $rating;
		}
		if ($critical == 0)
		{
			$ecrit = $price;
		}
		$rating = $hold_messages[$luck];
	}

	if ($bcrit != 0 && $ecrit != $bcrit)
	{
		$advice .= ": $bcrit - $ecrit";
	}
	return $advice;
}

sub PostBitcoinRating
{
	my $date = shift;
	my $rating = shift;
	my $message = "Willbot #Bitcoin Rating for $date: $rating";
	say "Length: " . length($message);
	say $message;
	if (IsActive())
	{
		PostToTimeline($message);
	}
}

sub GatherData
{
	my %terms;
	my $best1;
	my $best2;
	my $best3;

	my $wb = getLoginFor('wbic16');
	my $statuses = $wb->home_timeline({ count => 200 });
	for my $status (@$statuses)
	{
		my $cleanString = $status->{text};
		my @tmp = split(' ', $cleanString);
		for my $t (@tmp)
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

	my $message = $top[0] . ' ' . $best1 . ' ' . $top[1] . ' ' . $top[2] . ' ' . $best3;
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
	for my $c (@cleanup)
	{
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

	return $message;
}

sub PostToTimeline
{
	my $message = shift;
	my $nt = getLoginFor('wbic32');

	my $result = $nt->update($message);
	if (my $err = $@)
	{
		die $@ unless blessed $err && $err->isa('Net::Twitter::Error');
		warn "HTTP Response Code: ", $err->code, "\n",
				"HTTP Message......: ", $err->message, "\n",
				"Twitter error.....: ", $err->error, "\n";
	}
}

sub login
{
	my $consumer_key = shift;
	my $consumer_secret = shift;
	my $token = shift;
	my $token_secret = shift;

	my $handle = Net::Twitter->new(
    traits   => [qw/API::RESTv1_1/],
    consumer_key        => $consumer_key,
    consumer_secret     => $consumer_secret,
    access_token        => $token,
    access_token_secret => $token_secret,
	 ssl                 => 1
	);

	return $handle;
}
