package SOAP::Transport::HTTP::Daemon::Threaded;

use threads;

use strict;
use vars qw(@ISA);
use SOAP::Transport::HTTP;

@ISA = qw(SOAP::Transport::HTTP::Daemon);

sub handle {
  my $self = shift->new;
  
  # This works, but is not multi-threaded
  
  while (my $c = $self->accept) {
     while (my $r = $c->get_request) {
        $self->request($r);
        $self->SOAP::Transport::HTTP::Server::handle();
        $c->send_response($self->response);
        next;
     }
     $c->close;
     undef $c;    
  }
  
}

1;
