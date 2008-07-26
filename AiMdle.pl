#!/usr/bin/perl -w

use AiMdle;
use AiMdle::Config;
use AiMdle::Models::InMemory;

my %__CFG = (
   "usr"       => $SN,
   "pwd"       => $PWD,
   "ver"       => $VER,
   "runlatch"  => 1,
   "debug"     => 0,
);


$__CFG{'usr'} = $ARGV[0], if $ARGV[0];
$__CFG{'pwd'} = $ARGV[1], if $ARGV[1];

aimdle_main();

sub aimdle_main {
   print "AiMdle Bot v.$__CFG{ver} starting...\n";

   my $abot = $__a  = AiMdle->new('FirstBot');
   
   $abot->attach_model(AiMdle::Models::InMemory->new());
   $abot->debug_level($__CFG{'debug'});

   print "Signing onto OSCAR service as $__CFG{usr}\n";
   $abot->signon($__CFG{'usr'}, $__CFG{'pwd'});

   print "Entering AiMdle run_loop()\n\n";
   $abot->run_loop();

   print "\n\nShutting down...\n";
}

