-- Terminal Values.app: tv for people who'd rather click.
-- The installer compiles this on the member's own Mac (osacompile), so the
-- app is never downloaded and needs no signing.
--
-- Clicking it starts the box if it isn't running and opens the TV folder.
-- While the box runs, it shows tv status and offers Stop, Open pages and
-- Open folder.

on tv(args)
	-- do shell script has a bare PATH; runtimes live in these.
	set home to POSIX path of (path to home folder)
	return do shell script "PATH=/usr/local/bin:/opt/homebrew/bin:$PATH " & quoted form of (home & ".local/bin/tv") & " " & args
end tv

on openFolder()
	do shell script "open " & quoted form of tv("folder")
end openFolder

on run
	try
		set report to tv("status")
	on error errText number errNum
		if errNum is 3 then
			-- The box isn't running: start it and open the folder.
			try
				tv("start")
			on error startText
				display dialog "The box wouldn't start:" & return & return & startText buttons {"OK"} default button "OK" with icon caution with title "Terminal Values"
				return
			end try
			openFolder()
			display notification "TV's documents sync while it runs." with title "The box is running"
			return
		else if errNum is 1 then
			-- Running, but not on the tailnet or not yet syncing.
			set report to errText
		else
			display dialog errText buttons {"OK"} default button "OK" with icon caution with title "Terminal Values"
			return
		end if
	end try
	set choice to button returned of (display dialog "The box is running." & return & return & report buttons {"Stop", "Open pages", "Open folder"} default button "Open folder" with title "Terminal Values")
	if choice is "Open folder" then
		openFolder()
	else if choice is "Open pages" then
		tv("pages")
	else if choice is "Stop" then
		tv("stop")
		display notification "Documents won't sync until you start it again." with title "The box is stopped"
	end if
end run
