$( document ).ready(function() {


  var setPopupActive=function()
  {
	  
      $("#popup_box").html("<h2>Upgrade this Web Page?</h2>"+
    	       "<a id='popupBoxClose'>Close</a>"+
    		       "\n<table style='font-size: 14px; font-color: #555555; color: #555555;'>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$10*</b></td>"+
    		       "\n	<td>to host this page as is and remove this pop-up</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$50</b></td>"+
    		       "\n	<td>setup URL of your choice and first year hosting</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$30*</b></td>"+
    		       "\n	<td>URL hosting after first year</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$50</b></td>"+
    		       "\n	<td>setup Google based email for your URL</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$50</b></td>"+
    		       "\n	<td>to change page to image, text or html provided by you</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$100</b></td>"+
    		       "\n	<td>to setup online payments with PayPal</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$500</b></td>"+
    		       "\n	<td>to design and build a site from scratch, or one of these"+
    		       "\n		templates <a"+
    		       "\n		href='http://www.hongkiat.com/blog/60-high-quality-free-web-templates-and-layouts/'>[1]</a>"+
    		       "\n		<a href='http://www.freecsstemplates.org/'>[2]</a> <a"+
    		       "\n		href='http://www.webpagedesign.com.au/Free_Templates/'>[3]</a>"+
    		       "\n	</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$50</b></td>"+
    		       "\n	<td>per hour for any other help, changes and admin you may"+
    		       "\n		require.</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td><b>$120*</b></td>"+
    		       "\n	<td>a subscription that covers your URL hosting and 3 hours of"+
    		       "\n		help/support per year.</td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td colspan='2' style='font-size: 10px'><i><br>[*]"+
    		       "\n			indicates a yearly subscription</i></td>"+
    		       "\n</tr>"+
    		       "\n<tr>"+
    		       "\n	<td colspan='2' style='font-size: 10px'><i><br></i></td>"+
    		       "\n</tr>"+
    		       "\n</table>"+
    		       "\n<img src='http://www.gormantec.com/images/GT.png' width='130px' alt=''>"+
    		       "\n<span"+
    		       "\nstyle='position: relative; top: -40px; left: 20px; font-weight: bold; font-size: 16px; color: #666666;'>contact"+
    		       "\nCraig at : <span>craig</span>&#64;<span>gormantec</span>&#46;<span>com</span> or online <a href='http://www.gormantec.com/signup.html'>[here]</a>"+
    		       "\n</span>");
      $('#popupBoxClose').click( function() {            
          unloadPopupBox();
      });
      $('#container').click( function() {
    	  loadPopupBox();
      });
  };
  $.getJSON( "/details.json", function( json ) {
	  var text="";
	  for(var i = 0; i < json.length; i++) {
		    var obj = json[i];
		    if(obj.value)
		    {
		    	text=text+obj.value+"&nbsp;&nbsp;&nbsp;-&nbsp;&nbsp;&nbsp;";
		    }
		    if(obj.paid_up_site==='false')
		    {
		    	setPopupActive();
		    }
		    
		}
	  if(text.length>32 && document.getElementById('details'))
	  {
		  text=text.substring(0, text.length-31);
		  document.getElementById('details').innerHTML="<center>"+text+"</center>";
	  }});
  
  var auth_data=$.sessionStorage( 'auth_data' );  
  
  if(auth_data===null || auth_data==='undefined' || auth_data.verifiedEmail==='undefined')
	{
	  console.log('login :'+document.getElementById('loginButton'));
	  if(document.getElementById('loginButton'))
	  {
		  console.log('login button');
		  document.getElementById('loginButton').style.visibility='visible';
		  document.getElementById('loginButton').onclick=function(){console.log('login');window.location.href = "/login.html";}
	  }
	  
	}
  else
		{	
	  $.getJSON( "https://gorman-tec-au.appspot.com/auth.json?oauthAccessToken="+auth_data.oauthAccessToken, function( data ) {
		  console.log(data);
	  });
	  
		  console.log('logout :'+document.getElementById('loginButton'));
		    if(document.getElementById('loginButton'))
			{
				console.log('logout button');
				document.getElementById('loginButtonImg').src='//gorman-tec-au.appspot.com/images/chrfb/system_white/HARDWAREOUT_32x32-32.png';
				document.getElementById('loginButton').style.visibility='visible';
				document.getElementById('myAccountButton').style.visibility='visible';
				document.getElementById('loginButton').onclick=function(){
					console.log('logout');window.location.href = "/logout.html";
					document.getElementById('myAccountButton').style.visibility='hidden';
				}
			}
		}
	  
	//});
  
});  

     jQuery.fn.center = function () {
	    this.css("position","absolute");
	    this.css("top", Math.max(0, (($(window).height() - $(this).outerHeight()) / 2) + $(window).scrollTop()) + "px");
	    this.css("left", Math.max(0, (($(window).width() - $(this).outerWidth()) / 2) +  $(window).scrollLeft()) + "px");
	    return this;
	}
 

      function unloadPopupBox() {    // TO Unload the Popupbox
          $('#popup_box').fadeOut("slow");
          $("#container").css({ // this is just for style        
              "opacity": "1"  
          }); 
      }    
      
      function loadPopupBox() {    // To Load the Popupbox
    	  $("#popup_box").center();
          $('#popup_box').fadeIn("slow");
          $("#container").css({ // this is just for style
              "opacity": "0.3"  
          });         
      }        
  
