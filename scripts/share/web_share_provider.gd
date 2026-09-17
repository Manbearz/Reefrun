extends ShareProvider

var _js_done: JavaScriptObject
var _busy := false
var _installed := false


func is_busy() -> bool:
	return _busy


func share_image(bytes: PackedByteArray) -> String:
	if _busy:
		return "busy"
	if bytes.is_empty():
		share_finished.emit("failed")
		return "failed"
	if not Engine.has_singleton("JavaScriptBridge"):
		return _download_local(bytes)
	_busy = true
	_install_js()
	var js := Engine.get_singleton("JavaScriptBridge")
	var window: Variant = js.get_interface("window")
	if window == null:
		_busy = false
		return _download_local(bytes)
	window.__reefrunSharePng = Marshalls.raw_to_base64(bytes)
	var result: Variant = js.eval("window.__reefrunDoShare()", true)
	var status := str(result)
	if status.is_empty():
		status = "failed"
	if status != "started":
		_busy = false
		share_finished.emit(status)
	return status


func _download_local(bytes: PackedByteArray) -> String:
	var path := "user://reefrun-run.png"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		share_finished.emit("failed")
		return "failed"
	file.store_buffer(bytes)
	file.close()
	share_finished.emit("saved")
	return "saved"


func _install_js() -> void:
	if _installed:
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var js := Engine.get_singleton("JavaScriptBridge")
	_js_done = js.create_callback(_on_js_share_done)
	js.eval(
		"""
		(function(){
			if (window.__reefrunShareInstalled) return;
			window.__reefrunShareInstalled = true;
			window.__reefrunSharePng = '';
			function b64ToBytes(b64){
				var binary = atob(b64);
				var len = binary.length;
				var bytes = new Uint8Array(len);
				for (var i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i);
				return bytes;
			}
			function downloadPng(b64){
				try {
					var a = document.createElement('a');
					a.href = 'data:image/png;base64,' + b64;
					a.download = 'reefrun-run.png';
					a.rel = 'noopener';
					document.body.appendChild(a);
					a.click();
					document.body.removeChild(a);
					return 'saved';
				} catch (e) {
					return 'failed';
				}
			}
			function canShareFiles(file){
				try {
					return !!(navigator.canShare && navigator.canShare({ files: [file] }));
				} catch (e) {
					return false;
				}
			}
			function done(status){
				try {
					if (window.__reefrunOnShareDone) window.__reefrunOnShareDone(status);
				} catch (e) {}
			}
			window.__reefrunDoShare = function(){
				var b64 = window.__reefrunSharePng || '';
				window.__reefrunSharePng = '';
				if (!b64) return 'failed';
				try {
					if (typeof navigator === 'undefined' || typeof navigator.share !== 'function') {
						return downloadPng(b64);
					}
					var bytes = b64ToBytes(b64);
					var blob = new Blob([bytes], { type: 'image/png' });
					var file = new File([blob], 'reefrun-run.png', { type: 'image/png' });
					if (!canShareFiles(file)) {
						return downloadPng(b64);
					}
					navigator.share({
						files: [file]
					}).then(function(){
						done('ok');
					}).catch(function(){
						done('cancel');
					});
					return 'started';
				} catch (e) {
					return downloadPng(b64);
				}
			};
		})();
		""",
		true
	)
	var window: Variant = js.get_interface("window")
	if window != null:
		window.__reefrunOnShareDone = _js_done
	_installed = true


func _on_js_share_done(args: Array) -> void:
	_busy = false
	var status := "ok"
	if not args.is_empty():
		status = str(args[0])
	share_finished.emit(status)
