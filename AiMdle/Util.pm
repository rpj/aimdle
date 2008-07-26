package AiMdle::Util;
require Exporter;

BEGIN { push @ISA, "Exporter"; }
@EXPORT = qw(
   secs_to_str
   strip_html
);

# Convert a value in seconds to a time string of format HH:MM:SS
sub secs_to_str {
   my $secs = shift;

   return sprintf("%02d:%02d:%02d",
      ($secs / 60 / 60), ($secs / 60), ($secs % 60));
}

# Strip HTML from the passed-in string.
sub strip_html {
   (my $__str = shift) =~ s/<\/?.*?>//ig;
   return $__str;
}

1;
