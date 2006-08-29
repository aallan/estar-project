function setup() {

   createGenericButton(
	document.getElementById("donePrefsButton"),"Done",hidePrefs,60);
   document.getElementById("donePrefsButton").display = "none";

   endDiv = document.getElementById( 'endpoint' );
   endDiv.innerHTML = currentEndpoint();   
   updateStatus();

}
