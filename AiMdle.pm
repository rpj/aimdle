# AiMdle main class
package AiMdle;

use AiMdle::Util;
use AiMdle::Config;
use Net::OSCAR qw/:standard/;

# Return a singleton instance of the AiMdle object, constructing
# it first if necessary.
sub new {
   my $c = shift;
   my $n = shift;
   my $s = {};

   bless $s, $c;
   $s->{'name'} = $n ? $n : 'DefaultName';

   # run initialization 
   return $s->init();
}

# Automatic sub called on object destruction
sub DESTROY { 
   print "$_[0]->{name} sent $_[0]->{msgs_sent} of $_[0]->{'msgs_queued'} queued, ",
      "recv'd $_[0]->{'msgs_recvd'}\n";
}

# Initalize the AiMdle object
sub init {
   my $s = shift;
   my $o;

   # setup 'member variables'
   $s->{'oscar'}           = $o = Net::OSCAR->new();
   $s->{'msgs_sent'}       =
    $s->{'msgs_recvd'}     =
    $s->{'debug'}          =
    $s->{'msgs_queued'}    = 0;
   $s->{'run_latch'}       = 1;
   $s->{'authed_admins'}   = [];
   

   # setup command callbacks
   $s->{'cmds'} = {
      'help'      => [\&cmd_help, 
         "<b>help</b> -- this command."],
      'register'  => [\&cmd_register,
         "<b>register [name] [class]</b> -- register this screen name as 'name'."],
      'admin'     => [\&cmd_admin],
      'whoami'    => [\&cmd_whoami,
         "<b>whoami</b> -- display information about your character."],
      'login'     => [\&cmd_login,
         "<b>login</b> -- Log back in and continue leveling."],
      'logout'    => [\&cmd_logout,
         "<b>logout</b> -- log out your currently-leveling character."],
   };

   # Internal-use message queues
   $s->{'__msg_queue'}  = [];
   $s->{'__msgs_out'}   = {};
   
   # make sure the OSCAR object knows who owns it
   $o->{'owner_obj'}    = $s;
   
   # register the myriad of callbacks
   $o->set_callback_signon_done(\&cb_signon_done);
   $o->set_callback_im_in(\&cb_im_in);
   $o->set_callback_im_ok(\&cb_im_ok);
   $o->set_callback_buddy_info(\&cb_buddy_info);
   $o->set_callback_buddylist_ok(\&cb_buddylist_ok);
   $o->set_callback_buddylist_error(\&cb_buddylist_error);
   $o->set_callback_buddy_in(\&cb_buddy_in);
   $o->set_callback_buddy_out(\&cb_buddy_out);

   return $s;
}

# Attach a data model to this AiMdle object
sub attach_model($) {
   $_[0]->{'model'}     = $_[1];
   $_[1]->{'owner_obj'} = $_[0];
}

# Set the debugging level (for our AiMdle obj and the OSCAR obj)
sub debug_level($) {
   $_[0]->{'debug'} = $_[1];
   $_[0]->{'oscar'}->loglevel($_[1]);
}

# Do a single processing loop
sub one_loop {
   my $s = shift;

   $s->{'model'}->check_levels();
   $s->{'oscar'}->do_one_loop();
   $s->flush_msgs_for(undef);
}

# The full run-loop
sub run_loop {
   my $s = shift;
   
   $s->one_loop(), while ($s->{'run_latch'});
}

# Sign this AiMdle object onto the OSCAR service
sub signon {
   my ($s, $u, $p) = @_;
   $_[0]->{'oscar'}->signon($u, $p);
}

# post a message into the message queue, to be sent at a later time
sub post_msg_to($$) {
   my ($s, $to, $msg) = @_;

   push @{$s->{'__msg_queue'}}, [$to, $msg];
}

# send all messages in the queue to the specified user
# if the username argument is undefined, will flush all messages in the queue
sub flush_msgs_for($) {
   my ($s, $to) = @_;
   my $c = 0;
   my @tlist = ();

   my @slist = reverse(@{$s->{'__msg_queue'}});
   while ($_ = pop(@slist)) {
      if ((!$to || $_->[0] eq $to) && ++$c) {
         $rid = $s->{'oscar'}->send_im($_->[0], $_->[1]);
         $s->{'__msgs_out'}->{"$rid"} = $_;
      } else {
         push @tlist, $_;
      }
   }

   @{$s->{'__msg_queue'}} = @tlist;
   $s->{'msgs_queued'} += $c;
   print "Sent $c msgs to $to\n", if $to;
}

# Returns a true value if the user is an authorized admin, false if not
sub user_is_admin {
   my $s = shift;
   my $who = shift;

   return grep(/$who/, @{$s->{'authed_admins'}});
}

# Remove an authorized admin from the runtime admin list
sub rem_authed_user {
   my $s = shift;
   my $user = shift;

   my @ad_arr = @{$s->{'authed_admins'}};

   for ($i = 0; $i < scalar(@ad_arr); $i++) {
      splice(@ad_arr, $i, 1), if ($ad_arr[$i] eq $user);
   }

   @{$s->{'authed_admins'}} = @ad_arr;
}

# Serialize the model to the filesystem
sub serialize_model {
   my ($s, $who, $file) = @_;

   unless ($s->{'model'}) {
      $s->post_msg_to($who, "No model defined!");
      return undef;
   }

   my $ret = $s->{'model'}->serialize($file);
   $s->post_msg_to($who, (!$ret ? "Database saved to '$file'" :
    "Error saving database to '$file': '$ret'"));
   return $ret;
}

# Shutdown AiMdle
sub shutdown {
   my ($s, $who, $file) = @_;

   $s->serialize_model($who, $file), if ($file);
   $s->post_msg_to($who, "Shutting down!");
   $s->{'run_latch'} = 0;
}

# # # #
# COMMANDS

# 'help' command
sub cmd_help {
   my ($o, $from) = @_;
   my $s = $o->{'owner_obj'};

   $s->post_msg_to($from, "Here are the commands I understand:");
   foreach (keys %{$s->{'cmds'}}) {
      $s->post_msg_to($from, $s->{'cmds'}->{$_}->[1]),
         if ($s->{'cmds'}->{$_}->[1]);
   }
}

# 'register' command
sub cmd_register {
   my ($o, $from, $msg) = @_;
   my $s = $o->{'owner_obj'};
   my @msgs = ();
   my $errmsg = undef;

   if ($msg =~ /register\s+(\w+?)\s+(.+)/i) {
      my $m = $s->{'model'};
      
      if (defined $m && !($errmsg = $m->reg_user($1, $2, $from))) {
         print "Adding $from to our buddy list\n";
         $o->get_info($from);
         $o->add_buddy("G", $from);
         $o->commit_buddylist();
 
         $s->post_msg_to($from, "Registration successfull!");
         $s->post_msg_to($from,
          "Your <b>Level 1 $2</b> named <b>$1</b> is now roaming the world and" .
          " will reach Level 2 in <b>" . secs_to_str($LVL_TIMES[1]) . "</b>.");
      }
   } else {
      $errmsg = "Incorrect registration command. See 'help'.";
   }
  
  if ($errmsg) {
      $s->post_msg_to($from, "Error in registration!");
      $s->post_msg_to($from, "\"$errmsg\"");
   }
   
   return scalar(@msgs);
}

# 'whoami' command 
sub cmd_whoami {
   my ($o, $from, $msg) = @_;
   my $s = $o->{'owner_obj'};
   my $char;

   if ($s->{'model'} && ($char = $s->{'model'}->get_char($from))) {
      my $ttl = $s->{'model'}->get_ttl_str($from);
      
      $s->post_msg_to($from, 
         "You are the mighty <b>Level $char->{level} $char->{class}</b> " .
         "named <b>$char->{name}</b>. Next level in <b>$ttl</b>. " .
         "$char->{name} is currently <b>logged " .
         ($char->{'online'}?"in":"out") . "</b>.");
   } else {
      $s->post_msg_to($from, "No character registered! Please use " .
         "the register command first.");
   }
}

sub cmd_login {
   my ($o, $from, $msg) = @_;
   my $s = $o->{'owner_obj'};
   my $char;

   if ($s->{'model'}) {
      if (defined ($char = $s->{'model'}->get_char($from))) {
         #my $ttl = $s->{'model'}->get_ttl_str($from);
         my $ttl = $char->{'get_my_ttl'}();
         
         if ($char->{'online'}) {
            $s->post_msg_to($from,
               "Your adventurer $char->{name} is already roaming " .
               "the world! Next level in <b>$ttl</b>");
         } else {
            $char->{'online'} = 1;
            $char->{'sess_start'} = time();

            $s->post_msg_to($from,
             "Welcome back <b>$char->{name}</b>! You are currently " .
             "<b>level $char->{level}</b>, and will reach your next " .
             "level in <b>$ttl</b>");
         }
      } else {
         $s->post_msg_to($from,
            "It looks like you haven't registered yet: " .
            "type <b>register [nickname] [class]</b> to get " .
            "started in your mighty quest.");
      }
   }
}

sub cmd_logout {
   my ($o, $from, $msg) = @_;
   my $s = $o->{'owner_obj'};
   my $char;

   if ($s->{'model'} && ($char = $s->{'model'}->get_char($from))) {
      $char->{'online'} = 0;
      $char->{'sess_end'} = time();

      $s->post_msg_to($from,
         "You're <b>Level $char->{level} $char->{class} " .
         "<i>$char->{name}</i></b> has logged off. Type <i>" .
         "login</i> to begin leveling again.");
   }
}
      
# Administrator command processing
sub cmd_admin {
   my ($o, $from, $msg) = @_;
   my @aargs = ();
   my $s = $o->{'owner_obj'};

   if ($msg =~ /^admin\s+(\w+?)(?:\s+(.*))?$/i) {
      my ($scmd, $args) = ($1, $2);

      if ($scmd eq 'auth') {
         if ($args eq $ADMIN_PWD) {
            push @{$s->{'authed_admins'}}, $from;
            $s->post_msg_to($from, "You've gained administrator access.");
         }
      } else {
         @aargs = split(/\s+/, $args), if ($args);

         if ($s->user_is_admin($from)) {
            
            # 'list'
            if ($scmd eq 'list') {
               # 'admins'
               if ($aargs[0] eq 'admins') {
                  $s->post_msg_to($from, "Connected admins:");
                  $s->post_msg_to($from, "+ $_"),
                   foreach (@{$s->{'authed_admins'}});
               } 
            
               # 'users'
               elsif ($aargs[0] eq 'users') {
                  $s->post_msg_to($from, "Registered users:");

                  if ($s->{'model'}) {
                     my $hr = $s->{'model'}->list_users();

                     foreach (keys %$hr) {
                        my $uh   = $hr->{$_};
                        my $ttl  = $s->{'model'}->get_ttl_str($_);
                        my $ac   = secs_to_str($uh->{'accum_time'});
                        
                        $s->post_msg_to($from, "+ <b>$uh->{name}, a <b>Level " .
                         "$uh->{level} $uh->{class}</b> owned by <i>$_</i>, will level " .
                         "in <b>$ttl</b>. Accumulated time: <b>$ac</b>. Currently <b>" .
                         ($uh->{'online'}?"online":"offline") . "</b>.");
                     }
                  }
               }

               else {
                  $s->post_msg_to($from, "List sub-commands: admins, users");
               }
            }

            # 'deluser'
            elsif ($scmd eq 'deluser' && $aargs[0]) {
               $s->{'model'}->del_user($aargs[0]);
               $s->post_msg_to($from, "User '$aargs[0]' deleted.");
            }
            
            # 'savedb'
            elsif ($scmd eq 'savedb' && $aargs[0]) {
               $s->serialize_model($from, $aargs[0]);
            }
            
            # 'help'
            elsif ($scmd eq 'help') {
               $s->post_msg_to($from, "Available admin commands:");
               $s->post_msg_to($from, "auth [pass] -- authenticate yourself");
               $s->post_msg_to($from, "list [what] -- lists stuff"); 
               $s->post_msg_to($from, "deluser [user] -- delete user");
               $s->post_msg_to($from, "savedb [file] -- save DB to file");
            }

            # 'shutdown'
            elsif ($scmd eq 'shutdown') {
               $s->serialize_model($from, $aargs[0]), if ($aargs[0]);
               $s->{'run_latch'} = 0;
            }

         } else {
            $s->post_msg_to($from, "You are not authorized to do that.");
         }
      }
   }
}

# # # #
# CALLBACKS

# Signon to OSCAR is complete
sub cb_signon_done {
   my $o = shift;

   print "Signon completed succesfully.\n";
   print "Buddy list:\n";
   print "\t* $_\n", foreach $o->buddies("G");
}

# IM has been received
sub cb_im_in {
   my ($o, $from, $msg, $away) = @_;
   my $s = $o->{'owner_obj'};

   $s->{'msgs_recvd'}++;
   $msg = strip_html($msg);

   print "Recv'd: '$msg' from $from\n";

   my $cmd = $s->{'cmds'}->{(split(/\s+/, $msg))[0]};
   
   if ($cmd && $cmd->[0]) {
      &{$cmd->[0]}($o, $from, $msg);
   } elsif (!$away) { 
      $s->post_msg_to($from, $WELCOME_MSG); 
   } 
}

# IM was delivered successfully
sub cb_im_ok { 
   my ($o, $to, $rid) = @_;
   my $s = $o->{'owner_obj'};
   my $val = $s->{'__msgs_out'}->{"$rid"};

   if ($val && $val->[0] eq $to) {
      $s->{'msgs_sent'}++; 
   } else {
      print "Failed to ACK msg ID $rid, re-queueing\n";
      $s->post_msg_to($val->[0], $val->[1]);
   }

   delete $s->{'__msgs_out'}->{"$rid"};
}

# Buddy profile info returned
sub cb_buddy_info {
   my ($o, $who, $buddy) = @_;

   print "Buddy '$who' has been online for ", 
      int($buddy->{'session_length'} / 60),  " minutes\n";
}

# Saving buddylist was successful
sub cb_buddylist_ok {
   print "Buddylist OK\n";
}

# Error saving buddylist
sub cb_buddylist_error {
   print "Buddylist ERROR\n";
}

# Buddy signed in
sub cb_buddy_in {
   my ($o, $who, $g, $bdata) = @_;
   my $s = $o->{'owner_obj'};
   my $ch;

   print "logon>\t$who\n";
   if ($s->{'model'} && ($ch = $s->{'model'}->get_char($who))) {
      $ch->{'online'} = 1;
      $ch->{'sess_start'} = time();
      $ch->{'level_start'} = $ch->{'sess_start'} -
         ($ch->{'sess_end'} - $ch->{'level_start'});
      
      $s->post_msg_to($who, "Welcome back <b>$ch->{name}</b>! You're ".
         "at <b>Level $ch->{level}</b>, and have <b>" .
         $s->{'model'}->get_ttl_str($who) . "</b> to Level " .
         ($ch->{'level'} + 1));
   }
}

# Buddy signed out
sub cb_buddy_out {
   my ($o, $who, $g) = @_;
   my $s = $o->{'owner_obj'};
   my $char;
   
   print "logoff>\t$who";
   if ($s->user_is_admin($who)) {
      $s->rem_authed_user($who);
      print ", was removed from admin list";
   } print "\n";

   if ($s->{'model'} && ($char = $s->{'model'}->get_char($who))) {
      $char->{'online'} = 0;
      $char->{'sess_end'} = time();
   }
}

1;
