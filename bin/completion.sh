TACO=taco

_taco()
{
	local cur prev
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
    
# FIXME: don't look at prev, look at [0] or whatever so that we can "show 123 abc def"

	if [[ "${prev}" == "show" ]] ; then
		COMPREPLY=( $(compgen -W "$($TACO list | grep -v 'Found no issues.' | cut -d':' -f1)" -- ${cur}) )
		return 0
	fi
}
complete -F _taco taco