-- Terminal Values.app: tv for people who'd rather click.
-- The installer compiles this on the member's own Mac (osacompile), so the
-- app is never downloaded and needs no signing beyond the Mac's own.
--
-- Each click asks tv check where things stand, and does the next thing:
--   no runtime      say which to install, and open its download page
--   runtime stopped offer to start it
--   not joined      ask for login, name, email and the invitation; tv join;
--                   show the three lines to send Danny
--   box stopped     start it, then as below
--   box running     tv status, with Stop, Open pages and Open folder
-- so every click ends in the same window, whatever state the box was in.

property appTitle : "Terminal Values"

on tvCommand(args)
	-- do shell script has a bare PATH; runtimes live in these.
	set home to POSIX path of (path to home folder)
	return "PATH=/usr/local/bin:/opt/homebrew/bin:$PATH " & quoted form of (home & ".local/bin/tv") & " " & args
end tvCommand

on tv(args)
	return do shell script tvCommand(args)
end tv

on tellThem(msg)
	display dialog msg buttons {"OK"} default button "OK" with title appTitle
end tellThem

on fail(msg)
	display dialog msg buttons {"OK"} default button "OK" with icon caution with title appTitle
end fail

on askFor(question, secret)
	if secret then
		return text returned of (display dialog question default answer "" with hidden answer with title appTitle)
	else
		return text returned of (display dialog question default answer "" with title appTitle)
	end if
end askFor

on openFolder()
	do shell script "open " & quoted form of tv("folder")
end openFolder

on startBox()
	try
		tv("start")
	on error errText
		fail("The box wouldn't start:" & return & return & errText)
		return false
	end try
	return true
end startBox

on showRunning()
	try
		set report to tv("status")
	on error errText number errNum
		-- 1: running, but not on the tailnet or not yet syncing.
		set report to errText
	end try
	set choice to button returned of (display dialog "The box is running: TV's documents sync while it runs." & return & return & report buttons {"Stop", "Open pages", "Open folder"} default button "Open folder" with title appTitle)
	if choice is "Open folder" then
		openFolder()
	else if choice is "Open pages" then
		tv("pages")
	else if choice is "Stop" then
		tv("stop")
		display notification "Documents won't sync until you start it again." with title "The box is stopped"
	end if
end showRunning

on join()
	tellThem("Let's join Terminal Values from this Mac. You'll need the login name you picked and the invitation Danny sent you (one line, starting tvjoin:).")
	set login to askFor("Your login name (short, lowercase, like sam):", false)
	set fullName to askFor("Your name, as it should appear in TV's history:", false)
	set email to askFor("Your email:", false)
	tellThem("Now copy the invitation Danny sent you: in Signal, select the whole line (it starts tvjoin:) and copy it. Then click OK. You don't paste it anywhere: the app takes it from the clipboard, and clears the clipboard after.")
	try
		set out to do shell script tvCommand("join --from-clipboard --login " & quoted form of login & " --name " & quoted form of fullName & " --email " & quoted form of email & " </dev/null")
	on error errText
		fail("That didn't work:" & return & return & errText & return & return & "Click the app again to retry, or ask in TV Signal.")
		return
	end try
	set lines3 to do shell script "printf '%s\\n' " & quoted form of out & " | grep -E '^(login|syncthing|age): '"
	set choice to button returned of (display dialog "You're on TV's tailnet. Send these three lines to Danny:" & return & return & lines3 & return & return & "Then save a copy of your secret key: in Terminal, tv export-key > tv-age-key.txt, keep that file somewhere safe (your password manager), and delete it here." buttons {"OK", "Copy the three lines"} default button "Copy the three lines" with title appTitle)
	if choice is "Copy the three lines" then set the clipboard to lines3
end join

on run
	set state to tv("check")
	if state is "no-runtime" then
		set choice to button returned of (display dialog "TV's box needs a container runtime. On this Mac, install Apple's container (the .pkg on its releases page), then click this app again." buttons {"Cancel", "Open the download page"} default button "Open the download page" with title appTitle)
		if choice is "Open the download page" then open location "https://github.com/apple/container/releases/latest"
		return
	end if
	if state is "runtime-stopped" then
		display dialog "The container runtime isn't running. Start it? (The first time, it downloads a small Linux kernel.)" buttons {"Cancel", "Start it"} default button "Start it" with title appTitle
		try
			tv("runtime-start")
		on error errText
			fail("It wouldn't start:" & return & return & errText)
			return
		end try
		set state to tv("check")
	end if
	if state is "not-joined" then
		join()
		return
	end if
	if state is "stopped" then
		if not startBox() then return
	end if
	showRunning()
end run
