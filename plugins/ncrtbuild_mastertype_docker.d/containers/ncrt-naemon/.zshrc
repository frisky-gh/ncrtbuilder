#### シェルパラメータ

HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=200

FIGNORE=~:.bak

USER=$( id )
USER=${USER#uid=*\(}
USER=${USER%%\)*}
HOME=~$USER

MAIL=/var/mail/${USER}
MAILCHECK=300

LOGCHECK=300

if [ -f /.jailname ] ; then
    read JAILNAME < /.jailname
    PROMPT="%U${USER}@$JAILNAME.%m%u:%24<...<%~%B%#%b "
else
    PROMPT="%U${USER}@%m%u:%24<...<%~%B%#%b "
fi

VISUAL=emacs

#### キーバインド

bindkey -e
bindkey "^[[A" history-beginning-search-backward
bindkey "^[OA" history-beginning-search-backward
bindkey "^[[B" history-beginning-search-forward
bindkey "^[OB" history-beginning-search-forward


#### エイリアス

alias ll='ls -ablF'
alias rm='rm -i'


#### 関数

title () {
    if [ "x$@" = x ] ; then
	echo -n "\e]0;`ps -p $$ -o user | tail -1`@`hostname`\a"
    else
	echo -n "\e]0;$*\a"
    fi
    # PROMPT="%{^[]0;%n@%m^G%}%U%m%u:%24<...<%~%B%#%b "
}


#### 補完


####

title $USER@`hostname`


