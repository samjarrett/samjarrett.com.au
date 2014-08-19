$(function() {
	$("a[href^='http']").attr('target', '_blank').on('click', function() {
		ga('send', 'event', 'Outbound Link', 'click', $(this).attr('href'));
	});
	$("a[href^='mailto:']").on('click', function() {
		ga('send', 'event', 'Mailto Link', 'click', $(this).attr('href'));
	});
	$("a[href^='tel:']").on('click', function() {
		ga('send', 'event', 'Tel Link', 'click', $(this).attr('href'));
	});
	

});