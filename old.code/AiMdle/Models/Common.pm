package AiMdle::Models::Common;
require Exporter;

BEGIN { push @ISA, "Exporter"; }

@EXPORT = qw($SUCCESS %ERR);

our $SUCCESS      = 0;

our %ERR = (
   "UNKNOWN"      => "I don't know what went wrong!",
   "USER_EXISTS"  => "This screenname already has a registered character",
   "BAD_FILE"     => "Bad filename."
);

1;
