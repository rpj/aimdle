#!/usr/bin/perl -w

use AiMdle::Testing;

sub help {
   print "Usage: $0 [username] [password] [bot_name] [filename]\n";
   exit(-1);
}

my ($user, $pass, $bot, $file) = @ARGV;

help(), unless ($file && $user && $pass && $bot);

my $test = AiMdle::Testing->new($file, $user, $pass, $bot);

print "Beginning tests listed in '$file'\n";
$test->run_tests();

$SIG{'INT'} = sub { $test->end_test(); };
