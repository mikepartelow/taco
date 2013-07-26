TACO=taco

_taco()
{
	local cur prev
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[COMP_CWORD-1]}"
    
	if [[ "${prev}" == "show" ]] ; then
		COMPREPLY=( $(compgen -W "$($TACO list | grep -v 'Found no issues.' | cut -d':' -f1)" -- ${cur}) )
		return 0
	fi
}
complete -F _taco taco