#=========================================================================
# @wbic32 Twitter Manager
# (c) 2013-2014 Will Bickford
# License: CC BY-SA 4.0 (http://creativecommons.org/licenses/by-sa/4.0/)
#=========================================================================
use strict;
use warnings;

use Net::Twitter;
use Scalar::Util 'blessed';
use POSIX;
use Time::Piece;
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

say "Running Mode: $mode";

our $config_file = 'willbot.config';
our $config = new Config::Simple($config_file);
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

	GiftRandomFollower();
	LoadBitcoinPriceData($date);
	PostBitcoinRating($date, GetBitcoinPriceRating());
	
	if (IsActive())
	{
		$config->write($config_file);
		say "Config Saved: ${config_file}...";
	}

	return 0;
}

sub GetWinners
{
	my $winners = $parms{'winners'};
	return @$winners;
}

sub GiftRandomFollower
{
	my @followers = GatherFollowers();
	my @possible_winners = ();
	my @winner_list = GetWinners();
	my %winners = map { $_ => 1 } @winner_list;
	foreach my $follower (@followers)
	{
		if (!exists($winners{$follower}))
		{
			push (@possible_winners, $follower);
		}
	}
	if ($#possible_winners == -1)
	{
		@possible_winners = @followers;
	}

   my $pick = int(rand($#possible_winners));
	my $amount = int(rand(1000)) + 50;
	my $winner = $possible_winners[$pick];
	my $message = "Today\'s Lucky Follower \@" . $winner . " gets $amount bits! \@changetip";
	say $message;
	if (IsActive())
	{
		push(@winner_list, $winner);
		$config->param("winners", \@winner_list);
		PostToTimeline($message);
	}
}

sub LoadBitcoinPriceData
{
	our %parms;
	my $date = shift;
	my $starting_date = $parms{'last_checked'};

	say "Looking up new values...";
	my $data = GetBitcoinAverageHash();
	my $btc_date = $data->{'timestamp'};
	my $price = $data->{'24h_avg'};
	
	my $format = '%a, %d %b %Y %H:%M:%S -0000';
	my $start = Time::Piece->strptime($starting_date, $format);
	my $end = Time::Piece->strptime($btc_date, $format);
	my $date_difference = $end - $start;
	if ($date_difference < 72000 || $date_difference > 98000)
	{
		say "You need to update last_checked to be within the last day.";
		$mode = 'dry-run';
	}
	else
	{
		# TODO: Use $date_difference to adjust averaging correctly
		if (IsActive())
		{		
			$config->param("last_price", $price);
		}
	}
	if (!IsActive())
	{
		$btc_date = $parms{'last_checked'};
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

sub CalculateNextEMA
{
	my $last_average = shift;
	my $price = shift;
	my $days = shift;
	my $denominator = floor($days / 2);
	my $factor = $denominator - 1;

	my $ema = RoundToTwoDecimals(($last_average * $factor + $price) / $denominator);
	return $ema;
}

sub WatchEMA
{
	my $prefix = shift;
	my $days = shift;
	my $price = shift;

	my $key = "${prefix}_day_ema";
	my $ema = $parms{$key};
	my $next_ema = CalculateNextEMA($ema, $price, $days);
	my $difference = RoundToTwoDecimals($next_ema - $ema);
	say "${days}-Day: $next_ema ($difference)";

	if (IsActive())
	{
		$config->param($key, $next_ema);
	}
}

sub GetBitcoinPriceRating
{
	my $rating = GetRandomHoldMessage();
	my $price = GetBitcoinAveragePrice();
	my $last_average = $parms{'last_average'};	
	my $next_average = CalculateNextEMA($last_average, $price, 60);

		# TODO: Do more than watch the 5 and 10-day EMAs
	WatchEMA('five', 5, $price);
	WatchEMA('ten', 10, $price);

	if (IsActive())
	{
		$config->param("last_average", $next_average);
	}
	say "Average: $next_average";
	my $critical = GetCriticalRating($price, $last_average, $next_average, 1);
	$rating = GetPriceRating($price, $next_average, $critical, $rating);

	# TODO: Publish this once it improves and @wbic16 has posted the blog article
	my $advice = rangeFinder($rating, $next_average, $last_average, 0.8, 1.2, $rating);
	say "Advice: $advice";

	return $rating;
}

sub GetPriceRating
{
	my $price = shift;
	my $ema = shift;
	my $critical = shift;
	my $rating = shift;

	if ($critical == 0   && $price > $ema * 1.05) { $rating = 'Soft Sell'; }
	if ($critical == 0   && $price > $ema * 1.11) { $rating = 'Peak Sell'; }
	if ($critical == 0.5 && $price > $ema * 1.25) { $rating = 'Spiking Sell'; }
	if ($critical == 0.5 && $ema * 0.75 > $price) { $rating = 'Dropping Buy'; }
	if ($critical == 0   && $ema * 0.95 > $price) { $rating = 'Valley Buy'; }

	return $rating;
}

sub GetCriticalRating
{
	my $price = shift;
	my $previousEma = shift;
	my $ema = shift;
	my $show = shift;

	my $difference = RoundToTwoDecimals($ema - $previousEma);
	if ($show)
	{
		say "Difference: $difference"
	}

	my $critical = 1;
	if (abs($difference) < 0.2)
	{
		$critical = 0;
	}
	elsif (abs($difference) < 1.0)
	{
		$critical = 0.5;
	}

	return $critical;
}

sub GetRandomHoldMessage
{
	my @hold_messages = (
		'Ho Ho Ho Hold! #HODL',
	  	'#HODLing like a boss',
	  	'Just keep keep holding, just keep holding ... what do we do we #HODL!',
		'What are you doing, #Bitcoiner? I can\'t help you right now. #HODL',
		'History will record this day as just another day. #HODL',
		'#HODL me baby, one more time.',
		'I am required to issue a #HODL rating by my benevolent overlord.',
		'A Bitcoin saved today is a Bitcoin earned tomorrow: #HODL',
		'Algorithm survey says: Try Again. Algorithm survey says: #HODL',
		'Hold the line folks. #HODL',
		'I\'m bored, let\'s memorize some digits of pi. 3.14159265358979 #HODL',
		'You can submit your own #HODL ideas by replying. #HODL'
	);
	my $list_size = $#hold_messages;
	my $luck = int(rand($list_size));

	return $hold_messages[$luck];
}

sub rangeFinder
{
	my $advice = shift;
	my $next_average = shift;
	my $last_average = shift;
	my $lower_bound = shift;
	my $upper_bound = shift;
	my $rating = shift;

	my $first_critical_value = 0;
	my $last_critical_value = 0;
	my $baseline_rating = $advice;
	my $min_price = RoundToTwoDecimals($next_average * $lower_bound);
	my $max_price = RoundToTwoDecimals($next_average * $upper_bound);
	my $iteration = RoundToTwoDecimals(($max_price - $min_price) / 100);
	for (my $price = $min_price; $price <= $max_price; $price += $iteration)
	{
		$next_average = CalculateNextEMA($last_average, $price, 60);

		my $critical = GetCriticalRating($price, $last_average, $next_average, 0);
		$rating = GetPriceRating($price, $next_average, $critical, $rating);

		if ($first_critical_value == 0 && $critical == 0)
		{
			$first_critical_value = RoundToTwoDecimals($price);
			$advice = $rating;
		}
		if ($critical == 0)
		{
			$last_critical_value = RoundToTwoDecimals($price);
		}
		$rating = GetRandomHoldMessage();
	}

	if ($first_critical_value != 0 && $last_critical_value != $first_critical_value)
	{
		$advice .= ": $first_critical_value - $last_critical_value";
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

sub GatherFollowers
{
	# TODO: Fix my illiteracy with perl data structures and Data::Dumper output
	# TODO: Never cache wbic16 or 'fake accounts'
	#my $wb32 = getLoginFor('wbic32');
	#foreach my $users ($wb32->followers->{'users'})
	#{
	#	say "====----====";
	#	say Dumper($users);
	#	say "----====----";
	#}
	
	# $config->param("followers", \@followers);
	my $followers = $parms{'followers'};
	return @$followers;
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
