# AiMdle testing framework
package AiMdle::Testing;

use Exporter;
use Net::OSCAR qw/:standard/;

BEGIN { push @ISA, "Exporter"; }
@EXPORT = qw(%TEST_ERR);

our %TEST_ERR = (
   "FNF"       => "Specified file not found.",
   "NO_FILE"   => "No input file has been specified.",
   "NO_U/P"    => "Username/password has not been specified.",
   "NO_BOT"    => "Bot screenname not specified.",
);

sub new {
   my ($c, $file, $u, $p, $bot) = @_;
   my $s = {};

   bless $s, $c;
   
   $s->{'file'}         = $file, if ($file);
   $s->{'user'}         = $u, if ($u);
   $s->{'pass'}         = $p, if ($p);
   $s->{'bot'}          = $bot, if ($bot);
   $s->{'file_lines'}   = [];
   $s->{'run_latch'}    = 1;
   $s->{'end_next'}     = undef;
   $s->{'wait_one'}     = 0;
   
   return $s->init_oscar();
}

sub set_file      { $_[0]->{'file'} = $_[1]; }
sub set_username  { $_[0]->{'user'} = $_[1]; }
sub set_password  { $_[0]->{'pass'} = $_[1]; }
sub set_botname   { $_[0]->{'bot'}  = $_[1]; }
sub end_test      { $_[0]->{'run_latch'} = 0; }

# returns $s (the AiMdle::Testing object) for chaining
sub init_oscar {
   my $s = shift;

   # to ensure a previous OSCAR object's resources are freed, if any
   $s->{'oscar'} = undef;
   
   my $o = $s->{'oscar'} = Net::OSCAR->new();
   
   $o->{'owner_obj'} = $s;
   
   $o->set_callback_signon_done(\&cb_signon_done);
   $o->set_callback_im_in(\&cb_im_in);
   
   return $s;
}

sub signon_oscar {
   my $s = shift;
   
   return $TEST_ERR{'NO_U/P'}, unless ($s->{'user'} && $s->{'pass'});
   $o->signon($s->{'user'}, $s->{'pass'});
}

sub run_tests {
   my $s = shift;
   my $o = $s->{'oscar'};
   my @tmp = ();

   return $TEST_ERR{'NO_FILE'}, unless ($s->{'file'});
   open (F, "$s->{file}") or return $TEST_ERR{'FNF'};

   while (<F>) {
      chomp;
      push @tmp, $_;
   }

   @{$s->{'file_lines'}} = reverse (@tmp); 

   close(F);

   $s->signon_oscar();

   while ($s->{'run_latch'}) { 
      $o->do_one_loop(); 

      # we need to wait a bit after we run out of lines to ensure
      # we've recv'd all messages from the aimdle bot
      if (defined $s->{'end_next'}) {
         $s->{'run_latch'} = 0, if (!($s->{'end_next'}--));
      }
   }
}

sub send_next {
   my $s = shift;
   
   my $line = pop @{$s->{'file_lines'}};

   unless (defined $line) {
      $s->{'end_next'} = 100;
      return;
   }

   if ($line =~ /^#\s*(.*)$/i) {
      print "\tCOMMENT \"$1\"\n";
      $s->send_next();
      return;
   }

   if ($line =~ /^!\s*(\d+)$/) {
      print "\tSLEEP $1 seconds\n";
      sleep($1);
      $s->send_next();
      return;  
   }

   if ($line =~ /^\>\s*(\w+)$/) {
      if ($1 eq 'logoff' && $s->{'online'}) {
         print "\tLOGOFF\n";
         $s->{'oscar'}->signoff();
         
         $s->{'online'} = 0;
         $s->send_next();
         
         return;
      } elsif ($1 eq 'logon' && !($s->{'online'})) {
         print "\tLOGON\n";

         $s->init_oscar()->signon_oscar();
         return;
      }
   }
   
   print "SEND> \t$line\n";
   $s->{'last_msg_id'} = $s->{'oscar'}->send_im($s->{'bot'}, $line);
}

sub cb_signon_done {
   my $o = shift;
   my $s = $o->{'owner_obj'};
   
   print "\tSignon successful\n";
   die $TEST_ERR{'NO_BOT'}, unless ($s->{'bot'});

   $s->{'online'} = 1;
   $s->send_next();
}

sub cb_im_in {
   my ($o, $from, $msg, $away) = @_;

   print "RECV> \t$msg\n";
   $o->{'owner_obj'}->send_next();
}

1;
