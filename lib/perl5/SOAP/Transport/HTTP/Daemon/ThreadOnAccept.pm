package SOAP::Transport::HTTP::Daemon::ThreadOnAccept;

use threads;
use threads::shared;

use strict;
use vars qw(@ISA);

# based on SOAP::Transport::HTTP::Daemon
use SOAP::Transport::HTTP;

@ISA = qw(SOAP::Transport::HTTP::Daemon);

sub handle {
  my $self = shift->new;

  while ( my $c = $self->accept) {
    print "Main: Accepting connection...\n";
    print "Main: Creating thread...\n";
    my $handler_thread = threads->create( sub { callback( $self, $c ) } );
    print "Main: detaching thread...\n";
    $handler_thread->detach();
    print "Main: Going to sleep for 5 seconds...\n";
    sleep(5);
    print "Main: Waking up, \$c should go out of scope now...\n";
    #$c->close;
    #next;
  }
  
}

sub callback {
  my $self = shift;
  my $c = shift;
  
  print "Thread: In callback() function...\n";
  print "Thread: Closing listening socket...\n";
  $self->close;  # Close the listening socket (always done in children)
  print "Thread: Socket closed...\n";

  # Handle requests as they come in
  while (my $r = $c->get_request) {
    print "Thread: Handling request...\n";
    $self->request($r);
    $self->SOAP::Transport::HTTP::Server::handle;
    print "Thread: Sending response...\n";
    $c->send_response($self->response);
  }
  print "Thread: Closing socket...\n";
  $c->close;
  print "Thread: Socket closed, returning...\n";
  return;
}


1;
