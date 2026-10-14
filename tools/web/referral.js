// Paste this on https://lunarent.gg before the game loads.
// It keeps ?ref= in localStorage under reefrun_ref so a same-origin ReefRun
// page can read it after navigation. It does not create an account, grant
// coins, or attribute an app-store install.
(function () {
	try {
		var params = new URLSearchParams(window.location.search);
		var ref = params.get("ref") || "";
		if (!ref) {
			return;
		}
		localStorage.setItem("reefrun_ref", ref);
	} catch (e) {}
})();
