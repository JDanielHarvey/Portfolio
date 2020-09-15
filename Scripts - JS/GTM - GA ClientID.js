
// Tag - use selector variable to modify the form element ID

<script>
(function(){
var selector = "input[name='input_17']"
document.querySelector(selector).value = "{{cjs - ga clientid}}"
}) ();
</script>



// CJS variable

function() {
	try {
	  var trackers = ga.getAll();
	  var i, len;
	  for (i = 0, len = trackers.length; i < len; i += 1) {
	     if (trackers[i].get('trackingId') === "UA-8552372-1") {
		return trackers[i].get('clientId');
	     }
	  }
	} catch(e) {}
	return 'false';
}