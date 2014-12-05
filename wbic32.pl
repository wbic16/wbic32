#=============================================================================================================
# @wbic32 Twitter Manager
# (c) 2013-2014 Will Bickford
# License: CC BY-SA 4.0 (http://creativecommons.org/licenses/by-sa/4.0/)
#=============================================================================================================
# Here's a text-plot of what # we're trying to do with EMA analysis. The points marked with a '-' are non-
# trading days. The points marked with a '+' are trading days.
#                                                   -
#                                                   -
#                                                   -
#                                                   -
#                                                   -
#                     -++-  -+-                     -
#                    -    --   ----                -
#         +         -              -----          -
#       -- ---     -                    -----   --
#     --      -   -                          -+-
# -++-         -+-
#
# Notice how we trigger buys and sells at _critical points in the price curve. If the price is rising or
# falling too quickly, we avoid trading because it is almost impossible to catch a falling knife or predict
# when a price spike will end.
#=============================================================================================================

# ------------------------------------------------------------------------------------------------------------
# Language features and packages
# ------------------------------------------------------------------------------------------------------------
use strict;
use warnings;
use Config::Simple;
use Data::Dumper;
use File::Slurp;
use File::Touch;
use JSON;
use LWP::Simple;
use Math::Round;
use Net::Twitter;
use POSIX;
use Scalar::Util 'blessed';
use Time::Piece;
use feature qw(say);
require 'login_credentials.inc';

# ------------------------------------------------------------------------------------------------------------
# Module Configuration
# ------------------------------------------------------------------------------------------------------------
# Change the values here to adjust behavior
#
my $mode = 'Active';
our $config_file = 'willbot.config';
my $version = '0.1.0.2';

# ------------------------------------------------------------------------------------------------------------
# Kickstart
# ------------------------------------------------------------------------------------------------------------
my $arg = shift;
if (!defined $arg) { $arg = $mode; }
our $config = new Config::Simple($config_file);
if ($config == 0)
{
	$config = new Config::Simple(syntax=>'simple');
}
our %parms = $config->vars();
exit(Main($arg));

# ------------------------------------------------------------------------------------------------------------
# IsActive
# ------------------------------------------------------------------------------------------------------------
# Returns 1 if our current mode is active. Returns '' otherwise.
#
sub IsActive
{
	return $mode eq 'Active';
}

# ------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------
# $command : the run-time command to pass {'' or 'dry-run' so far}
# ------------------------------------------------------------------------------------------------------------
# Handles high-level behavior for the bot. Currently this consists of gifting a random follower and posting
# a bitcoin price rating. Also writes config changes to disk if we're not in the dry-run mode.
#
sub Main
{
	my $command = shift;
	if ($command eq 'dry-run')
	{
		$mode = 'Dry-Run';
	}

	say "==================================";
	say "Willbot Bitcoin Price Detector Bot";
	say "==================================";
	say "Running Mode: $mode";
	say "Version: $version";

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

# ------------------------------------------------------------------------------------------------------------
# GetWinners
# ------------------------------------------------------------------------------------------------------------
# Fetches the list of winners from the config file.
#
sub GetWinners
{
	my $winners = $parms{'winners'};
	return @$winners;
}

# ------------------------------------------------------------------------------------------------------------
# PickRandomFollower
# ------------------------------------------------------------------------------------------------------------
# Compares the set of followers to the set of winners and draws a new winner from the set of followers who
# have not won yet. If the sets are equal, then it starts over with everyone having a chance again.
#
sub PickRandomFollower
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

	return (\@winner_list, \@possible_winners, int(rand($#possible_winners)));
}

# ------------------------------------------------------------------------------------------------------------
# GiftRandomFollower
# ------------------------------------------------------------------------------------------------------------
# Picks a random follower and then sends a random amount of bitcoin as a thank-you.
#
sub GiftRandomFollower
{
	my ($winner_list_ref, $possible_winners_ref, $pick) = PickRandomFollower();
	my @winner_list = @$winner_list_ref;
	my @possible_winners = @$possible_winners_ref;
	my $amount = nearest(0.01, rand(15)) + 2.5;
	my $winner = $possible_winners[$pick];
	my $message = "Today\'s Lucky Follower \@" . $winner . " gets $amount curseofbitcoin! \@changetip";
	say $message;
	if (IsActive())
	{
		push(@winner_list, $winner);
		$config->param("winners", \@winner_list);
		PostToTimeline($message);
	}
}

# ------------------------------------------------------------------------------------------------------------
# LoadBitcoinPriceData
# ------------------------------------------------------------------------------------------------------------
# $date : the date to compare the price data to, typically today's current date
# ------------------------------------------------------------------------------------------------------------
# Loads the 24-hour Bitcoin price rating from our data source, prints the average and updates the config file.
#
sub LoadBitcoinPriceData
{
	our %parms;
	my $date = shift;
	my $starting_date = $parms{'last_checked'};

	say "Looking up new values...";
	my $data = GetBitcoinAverageHash();
	my $btc_date = $data->{'timestamp'};
	my $price = $data->{'24h_avg'};
	if (! defined $price)
	{
		say "Error loading 24h_avg price data.";
		exit;
	}
	
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

# ------------------------------------------------------------------------------------------------------------
# GetBitcoinAverageHash
# ------------------------------------------------------------------------------------------------------------
# Returns the json content from bitcoinaverage.com as a hash.  Single-point of failure for price prediction.
#
sub GetBitcoinAverageHash
{
	my $url = "https://api.bitcoinaverage.com/ticker/USD/";
	my $content = get $url;
	return decode_json $content;
}

# ------------------------------------------------------------------------------------------------------------
# GetBitcoinAveragePrice
# ------------------------------------------------------------------------------------------------------------
# Decodes the json content provided by GetBitcoinAverageHash and returns the 24-hour average price.
#
sub GetBitcoinAveragePrice
{
	my $key = '24h_avg';
	my $data = GetBitcoinAverageHash();
	my $price = $data->{$key};
	say "Price: $price";
	return $price;
}

# ------------------------------------------------------------------------------------------------------------
# CalculateNextEMA
# ------------------------------------------------------------------------------------------------------------
# $last_average : yesterday's EMA to use as a baseline (use a simple average to get started)
# $price        : today's 24-hour average price
# $days         : number of days to consider for the EMA
# ------------------------------------------------------------------------------------------------------------
# Re-calculates the smoothed exponential moving average for a given number of days.
#
sub CalculateNextEMA
{
	my $last_average = shift;
	my $price = shift;
	my $days = shift;
	my $denominator = floor($days / 2);
	my $factor = $denominator - 1;

	my $ema = nearest(0.01, ($last_average * $factor + $price) / $denominator);
	return $ema;
}

# ------------------------------------------------------------------------------------------------------------
# WatchEMA
# ------------------------------------------------------------------------------------------------------------
# $prefix             : string prefix for the config file (i.e. 'six', 'ten')
# $days               : numeric number of days for the EMA to watch
# $price              : today's 24-hour average price
# $primary_difference : today's primary EMA difference
# ------------------------------------------------------------------------------------------------------------
# I'm using this to watch the 6-day and 10-day EMAs to see if there are correlations in critical points on
# trading days. I hope to improve the quality of my critical point detection by watching them.
#
sub WatchEMA
{
	my $prefix = shift;
	my $days = shift;
	my $price = shift;
	my $primary_difference = shift;

	my $key = "${prefix}_day_ema";
	my $ema = $parms{$key};
	my $next_ema = CalculateNextEMA($ema, $price, $days);
	my $difference = nearest(0.01, $next_ema - $ema);
	say "${days}-Day: $next_ema ($difference)";

	my $critical = ($difference < 0 && $primary_difference > 0) ||
	               ($difference > 0 && $primary_difference < 0);
	if ($critical)
	{
		say "^-- Interesting data point";
	}

	if (IsActive())
	{
		$config->param($key, $next_ema);
	}
}

# ------------------------------------------------------------------------------------------------------------
# GetEMAInformation
# ------------------------------------------------------------------------------------------------------------
# $key   : text key to get yesterday's value from the config file
# $price : today's price
# $days  : number of days in the window
# ------------------------------------------------------------------------------------------------------------
# I abstracted these three calculations so I could easily repeat them for 6-day and 10-day EMAs.
#
sub GetEMAInformation
{
	my $key = shift;
	my $price = shift;
	my $days = shift;

	my $last = $parms{$key};
	my $next = CalculateNextEMA($last, $price, $days);
	my $diff = nearest(0.01, $next - $last);

	return ($last, $next, $diff);
}

# ------------------------------------------------------------------------------------------------------------
# GetBitcoinPriceRating
# ------------------------------------------------------------------------------------------------------------
# Calculates today's rating and advice. Advice is only printed to the screen for the moment.
# Returns today's price rating (text format).
#
sub GetBitcoinPriceRating
{
	my $rating = GetRandomHoldMessage();
	my $price = GetBitcoinAveragePrice();
	
	my ($last_average, $next_average, $difference) = GetEMAInformation('last_average', $price, 60);

	say "Potential: " . GetMarketPotential($price);

	# TODO: Do more than watch the 6-day and 10-day EMAs?
	WatchEMA('six', 6, $price, $difference);
	WatchEMA('ten', 10, $price, $difference);

	if (IsActive())
	{
		$config->param("last_average", $next_average);
	}
	say "Average: $next_average";
	my $critical = GetCriticalRating($price, $last_average, $next_average, 1);
	$rating = GetPriceRating($price, $next_average, $critical, $rating);

	# TODO: Publish this once it improves and @wbic16 has posted the blog article
	my $advice = RangeFinder($rating, $next_average, $last_average, 0.5, 2.0, $rating);
	say "Advice: $advice";

	return $rating;
}

# ------------------------------------------------------------------------------------------------------------
# GetMarketPotential
# ------------------------------------------------------------------------------------------------------------
# $price    : today's price
# ------------------------------------------------------------------------------------------------------------
# WIP: I intend to have this compute the market potential for today by taking into account each of the EMA
# trends we watch. I want to issue a [-10%, +10%] rating near critical points in the 60-day EMA.
#
sub GetMarketPotential
{
	my $price = shift;
	my $potential = 0;

	my %ema_hash = (
		6  => [ GetEMAInformation('six_day_ema', $price, 6) ],
		10 => [ GetEMAInformation('ten_day_ema',  $price, 10) ],
		60 => [ GetEMAInformation('last_average', $price, 60) ]
	);

	for my $days (keys %ema_hash)
	{
		my $last_average = $ema_hash{$days}[0];
		my $next_average = $ema_hash{$days}[1];
		my $diff         = $ema_hash{$days}[2];
		my $percentage   = $diff / $next_average * 100;

		$potential += ($percentage * $days);
	}

	return nearest(0.01, $potential);
}

# ------------------------------------------------------------------------------------------------------------
# GetPriceRating
# ------------------------------------------------------------------------------------------------------------
# $price    : today's 24-hour average price
# $ema      : today's 60-day smoothed EMA
# $critical : critical point indicator { 0 = not critical, 0.5 = somewhat, 1.0 = definitely }
# $rating   : the baseline #HODL message
# ------------------------------------------------------------------------------------------------------------
# Compares today's price to today's EMA and issues buy or sell advice. Not very well designed atm. Needs work.
#
# TODO:
# * Provide a range of 1% to 10% long-term holdings buy or sell advice
# * Certainty of sell or buy corresponds to how much we advise trading on a given day
#
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

# ------------------------------------------------------------------------------------------------------------
# GetCriticalRating
# ------------------------------------------------------------------------------------------------------------
# $price       : today's 24-hour average price
# $previousEma : yesterday's primary EMA
# $ema         : today's primary EMA
# $show        : print suppression (used when calling this from a loop)
# ------------------------------------------------------------------------------------------------------------
# Compares yesterday's EMA to today's and marks the difference critical as follows. This isn't a scalable
# method. Needs to be re-worked to scale with the price.
#
# If the values differ by...
# 0.0 : $1/BTC or more
# 0.5 : $0.20/BTC to $1.00/BTC
# 1.0 : $0.20/BTC to $0.00/BTC
#
# TODO:
# * Use more than 1 day of history to avoid 1-day price gaming
# * Adjust the critical ranges with the price
# * Make the critical rating continuous (affects GetPriceRating)
#
sub GetCriticalRating
{
	my $price = shift;
	my $previousEma = shift;
	my $ema = shift;
	my $show = shift;

	my $difference = nearest(0.01, $ema - $previousEma);
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

# ------------------------------------------------------------------------------------------------------------
# GetRandomHoldMessage
# ------------------------------------------------------------------------------------------------------------
# Holds a list of potential #HODL messages to reduce boredom. Currently, I'm targeting 85-90% of days as hold
# advice days, so this helps keep followers engaged. Needs moar ratings!
#
sub GetRandomHoldMessage
{
	my @hold_messages = (
		'Ho Ho Ho Hold! #HODL',
	  	'#HODLing like a boss',
	  	'Just keep holding, just keep holding ... what do we do we #HODL!',
		'What are you doing, #Bitcoiner? I can\'t help you right now. #HODL',
		'History will record this day as just another day. #HODL',
		'#HODL me baby, one more time.',
		'I am required to issue a #HODL rating by my benevolent overlord.',
		'A Bitcoin saved today is a Bitcoin earned tomorrow: #HODL',
		'Algorithm survey says: Try Again. Algorithm survey says: #HODL',
		'Hold the line folks. #HODL',
		'I\'m bored, let\'s memorize some digits of pi. 3.14159265358979 #HODL',
		'Tip: You can submit your own #HODL ideas by replying. #HODL',
		'Take a look at #linktrace while you #HODL today.',
		'Keep Calm and #HODL On http://www.keepcalm-o-matic.co.uk/p/keep-calm-and-hodl-on/',
		'Repeat after me: H, o, l, d. What does that spell? #HODL'
	);
	my $list_size = $#hold_messages;
	my $luck = int(rand($list_size));

	return $hold_messages[$luck];
}

# ------------------------------------------------------------------------------------------------------------
# RangeFinder
# ------------------------------------------------------------------------------------------------------------
# $advice       : baseline advice
# $next_average : today's EMA
# $last_average : yesterday's EMA
# $lower_bound  : lowest expected price today
# $upper_bound  : highest expected price today
# $rating       : baseline rating
# ------------------------------------------------------------------------------------------------------------
# Iterates over the range specified by the bound arguments in 100 steps. Looks for conditions that would cause
# our trading advice to change. Due to the nature of the critical point detection, we'll only ever have one
# range, if any. If a range is found, this method returns the revised advice and the price range that
# generated it. I'm not using this yet because I need to write a blog post explaining how to utilize it.
#
sub RangeFinder
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
	my $min_price = nearest(0.01, $next_average * $lower_bound);
	my $max_price = nearest(0.01, $next_average * $upper_bound);
	my $iteration = nearest(0.01, ($max_price - $min_price) / 100);
	for (my $price = $min_price; $price <= $max_price; $price += $iteration)
	{
		say "Potential @ " . nearest(0.01, $price) . ": " . GetMarketPotential($price);

		$next_average = CalculateNextEMA($last_average, $price, 60);

		my $critical = GetCriticalRating($price, $last_average, $next_average, 0);
		$rating = GetPriceRating($price, $next_average, $critical, $rating);

		if ($first_critical_value == 0 && $critical == 0)
		{
			$first_critical_value = nearest(0.01, $price);
			$advice = $rating;
		}
		if ($critical == 0)
		{
			$last_critical_value = nearest(0.01, $price);
		}
		$rating = GetRandomHoldMessage();
	}

	if ($first_critical_value != 0 && $last_critical_value != $first_critical_value)
	{
		$advice .= ": $first_critical_value - $last_critical_value";
	}
	return $advice;
}

# ------------------------------------------------------------------------------------------------------------
# PostBitcoinRating
# ------------------------------------------------------------------------------------------------------------
# $date   : the date to report, usually today's date
# $rating : the rating to post
# ------------------------------------------------------------------------------------------------------------
# Constructs our price rating tweet and posts it to twitter if we're in the active mode.
#
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

# ------------------------------------------------------------------------------------------------------------
# GatherFollowers
# ------------------------------------------------------------------------------------------------------------
# STUB: Needs to scan my twitter followers and update the follower list dynamically. I've been managing it by
# hand so far.
#
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

# ------------------------------------------------------------------------------------------------------------
# PostToTimeline
# ------------------------------------------------------------------------------------------------------------
# $message : the message to post
# ------------------------------------------------------------------------------------------------------------
# Wrapper for posting messages as @wbic32 on twitter.
#
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

# ------------------------------------------------------------------------------------------------------------
# login
# ------------------------------------------------------------------------------------------------------------
# $consumer_key    : OAuth consumer key
# $consumer_secret : OAuth consumer secret
# $token           : OAuth access token
# $token_secret    : OAuth access token secret
# ------------------------------------------------------------------------------------------------------------
# See http://search.cpan.org/dist/Net-Twitter/lib/Net/Twitter.pod for more information.
#
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
