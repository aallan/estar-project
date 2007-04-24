#!/usr/bin/perl

use strict;
use warnings;

# shared_hash.pl - A simple proof of concept for sharing variables between
# multiple threads.

use threads;
use threads::shared;


# The variable to be shared. An unshared variable is copied to each thread and
# becomes private to that thread. There is no locking on a shared variable by
# default. Explicit locking is not required if different threads are writing
# to different parts of the data structure.
my %blackboard;
share(%blackboard);


# Start up the threads...
my $thread1 = threads->create(\&update_bb, 'update1', 1, 1);
my $thread2 = threads->create(\&read_bb, 'read1');

my $thread3 = threads->create(\&update_bb, 'update2', 15, 2);

# Wait for the threads to return...
$thread1->join();
$thread2->join();
$thread3->join();

sleep 2;
# Print out the final state of the blackboard...
print "Final bb status:\n";
print_bb();

sub update_bb {
   my $name      = shift;
   my $start_val = shift;
   my $sleep_interval = shift;

   my $val = $start_val;
   
   for ( 1..5 ) {
      print "Thread $name executing iteration $_...\n";
      $blackboard{$name} = $val;
      $val++;
      sleep $sleep_interval;
   }
   
   return;
}


sub read_bb {
   my $name = shift;

   for ( 1..18 ) {
      print "Thread $name executing iteration $_...\n";
      print "Reading blackboard:\n";
 
      print_bb();
      
      sleep 1;
   }
}


sub print_bb {
   foreach my $key ( keys %blackboard ) {
      print "[$key] => [$blackboard{$key}]\n";
   }
}
