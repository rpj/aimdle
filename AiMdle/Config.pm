package AiMdle::Config;
require Exporter;

BEGIN { push @ISA, "Exporter"; }

@EXPORT        = qw(
   $SN 
   $PWD 
   $VER 
   $ADMIN_PWD 
   $WELCOME_MSG
   @LVL_TIMES
);

our $SN           = 'AiMdleBot';
our $PWD          = '';
our $VER          = 0.07;
our $ADMIN_PWD    = 'bad_pass';
our $WELCOME_MSG  = "Hello there! I'm AiMdleBot, and if you type " .
   "'help' to me, I'll let you know what you can do!";

our @LVL_TIMES    = (0, 60, 120, 240, 480, 1000, 2500, 9000000);

1;
