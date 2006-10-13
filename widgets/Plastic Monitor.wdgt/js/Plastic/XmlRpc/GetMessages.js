var getMessages = {


   // creates an XMLHttpRequest instance
   createXmlHttpRequestObject: function() 
   {
     // will store the reference to the XMLHttpRequest object
     var xmlHttp;
     // this should work for all browsers except IE6 and older
     try
     {
       // try to create XMLHttpRequest object
       xmlHttp = new XMLHttpRequest();
     }
     catch(e)
     {
  
     }
     // return the created object or display an error message
     if (!xmlHttp)
       alert("Error creating the XMLHttpRequest object.");
     else 
       return xmlHttp;
   },

   // the function handles that handles updating the document
   makeRequest: function( $plid )
   {

      if(window.console) {
         window.console.log("Called getMessages.makeRequest()");
      }

      var XmlRpc = new XMLRPCMessage(["plastic.hub.getUnderstoodMessages"]);
      XmlRpc.addParameter( $plid );
  
      var message = XmlRpc.xml();
      

      xmlHttp['understoodMessages'] = getMessages.createXmlHttpRequestObject(); 
      var serverAddress = plastic.xmlrpcEndpoint();

      // only continue if xmlHttp['understoodMessages'] isn't void
      if (xmlHttp['understoodMessages'])
      {
  
        // try to connect to the server
        try
        {
          // continue only if the XMLHttpRequest object isn't busy
          // and the cache is not empty
          if ( xmlHttp['understoodMessages'].readyState == 4 ||
	       xmlHttp['understoodMessages'].readyState == 0 )
          {
 
            xmlHttp['understoodMessages'].open("POST", serverAddress, true);
            xmlHttp['understoodMessages'].setRequestHeader("Content-Type", "text/xml");
            xmlHttp['understoodMessages'].onreadystatechange =
	                            getMessages.handleRequestStateChange;
            xmlHttp['understoodMessages'].send( '<?xml version="1.0"?>' + message);
	   
          }
        }
        catch (e)
        {
          // display an error when failing to connect to the server
          alert(e.toString());
        }
     }
   },	
	

   // function that handles the HTTP response
   handleRequestStateChange: function() 
   {
     
     if(window.console) {
           window.console.log("Called getMessages.handleReqestStateChange(" +
	                   xmlHttp['understoodMessages'].readyState + ")");
     }

   // when readyState is 4, we read the server response
   if (xmlHttp['understoodMessages'].readyState == 4) 
   {
      // continue only if HTTP status is "OK"
      if (xmlHttp['understoodMessages'].status == 200) 
      {
        try
        {
          // read the response from the server
          getMessages.readResponse();
        }
        catch(e)
        {
          // display error message
          alert(e.toString());
        }
      }
      else
      {
        // display error message
        alert(xmlHttp['understoodMessages'].statusText);
      }
    }
  },

  // read server's response 
  readResponse: function()
  {

    if ( window.console ) {
      window.console.log("Called getMessages.readResponse()");
    }

    // retrieve the server's response 
    var response;
    try 
    {
       //response = xmlHttp['understoodMessages'].responseText;
       response = xmlHttp['understoodMessages'].responseXML;
    }
    catch(e)
    {
        // display error message
        if( window.console) {
           window.console.log(
	     "Error: response = xmlHttp['understoodMessages'].response;" );
           window.console.log( "Error: " + e.toString() );
        }
        alert(e.toString());
    }

    //if(window.console) {
    //      window.console.log( response );
    //}

    // server error?
    //if (response.indexOf("ERRNO") >= 0 || 
    //    response.indexOf("error:") >= 0 || response.length == 0) {
    //  throw(response.length == 0 ? "Server error." : response);
    //}
   
    //response = response.replace( /</g, "&lt;" );
    //response = response.replace( />/g, "&gt;<br>" );
    //div = document.getElementById( 'selectedMessages' );
    //div.innerHTML = "<pre>" + response +"</pre>"; 
   
    var messages = response.getElementsByTagName("value");
    var html = "<ul>";
    for ( var j =0; j < messages.length; j++ ) {
       //html = html + "<li>" + j + "</li>";
       if ( messages[j].firstChild.nodeValue != null ) {
          html = html + "<li>" + messages[j].firstChild.nodeValue + "</li>";
       }  
    }
    html = html + "</ul>";
    messDiv = document.getElementById( 'selectedMessages' );
    messDiv.innerHTML = html;  
	  
	  
   }      
    
}


