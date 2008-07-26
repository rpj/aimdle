# AiMdle::Models::InMemory
# Specifies a rudimentary in-memory data model: really only useful for
# testing, although the serialize() method does allow re-use of these DBs.
package AiMdle::Models::InMemory;

use AiMdle;
use AiMdle::Util;
use AiMdle::Config;
use AiMdle::Models::Common;

# Construct a new InMemory data model
sub new {
   my $c = shift;
   my $s = {};

   bless $s, $c;

   $s->{'reged_users'} = {};
   return $s;
}

# Register a user, only if this screenname hasn't yet done so
sub reg_user {
   my ($s, $u, $c, $w) = @_;

   if (!defined($s->{'reged_users'}->{$w})) {
      my $now = time();
      
      $s->{'reged_users'}->{$w} = { 
         'name'         => $u,
         'class'        => $c, 
         'level'        => 1,
         'online'       => 1,
         'accum_time'   => 0,
         'sess_start'   => $now, 
         'sess_end'     => undef,
         'level_start'  => $now,
         'time_mark'    => $now,
      };
      
      return $SUCCESS;
   } else { return $ERR{'USER_EXISTS'}; }

   return $ERR{'UNKNOWN'};
}

# Get the users TTL in seconds
sub get_ttl {
   my ($s, $w) = @_;
   my $char = $s->{'reged_users'}->{$w};

   return undef, unless ($char);

   return $LVL_TIMES[$char->{'level'}] - 
    (($char->{'online'} ? time() : $char->{'sess_end'}) - 
    $char->{'level_start'});
}

# Get the TTL for user $_[1], formatted as a time string (HH:MM:SS)
sub get_ttl_str {
   return secs_to_str($_[0]->get_ttl($_[1]));
}

# Check each registered character that is online: if their TTL has dropped
# to 0, they've leveled, so do leveling things.
sub check_levels {
   my $s = shift;

   foreach (keys %{$s->{'reged_users'}}) {
      my $ch  = $s->{'reged_users'}->{$_};
      my $ttl = $s->get_ttl($_);

      next, unless ($ch->{'online'});
   
      my $now = time();
      $ch->{'accum_time'} += ($now - $ch->{'time_mark'});
      $ch->{'time_mark'} = $now;

      if ($ttl <= 0) {
         print "$ch->{name} just leveled!\n";
         
         ++$ch->{'level'};
         $ch->{'level_start'} = time();
         $ttl = $s->get_ttl_str($_);
         
         # $s->chance_battle();
         # $s->chance_item_pickup();
         # $s->chance_calamity();
         
         $s->{'owner_obj'}->post_msg_to($_,
            "Your <b>$ch->{class} $ch->{name}</b> just reached " .
            "<b>Level $ch->{level}</b>! Next level in <b>$ttl</b>");
      }
   }
}

# Returns a hash ref describing the character for the screenname
# specified by the argument to this function
sub get_char {
   return $_[0]->{'reged_users'}->{$_[1]};
}

# Return a hash ref of all registered users
sub list_users {
   return $_[0]->{'reged_users'};
}

# Delete a user's character from the game
sub del_user {
   # need to remove user from our buddy list here too!
   return delete $_[0]->{'reged_users'}->{$_[1]};
}

# Write the current database out to file (since it's in memory,
# this is pretty damn important!)
sub serialize {
   my ($s, $f) = @_;

   open (F, "+>./$f") or return $ERR{'BAD_FILE'};
   print F "# type=AiMdle::Models::InMemory\n";
   
   foreach (keys %{$s->{'reged_users'}}) {
      my $ch = $s->{'reged_users'}->{$_};
   
      print F "$_|$ch->{name}|$ch->{class}|$ch->{level}|".
         "$ch->{accum_time}|$ch->{sess_start}|$ch->{level_start}\n";
   }

   close(F);
   return $SUCCESS;
}

1;
