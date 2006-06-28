package Echo;

  sub echo {  
    $class = shift;
    $message = shift;
    return "ACK ($message)\n";     
  }
  
1;
