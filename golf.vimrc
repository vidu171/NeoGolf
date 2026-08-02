" golf.vimrc -- Neovim leveling config for VimGolf, adapted from the official
" vimgolf.vimrc. Neovim is always nocompatible and has no t_* terminal option
" strings, so those lines are omitted; the visible behaviour matches.

set scrolloff=3         " keep 3 lines when scrolling
set autoindent          " auto-indent for programming

set showcmd             " display incomplete commands
set nobackup            " do not keep a backup file
set number              " show line numbers
set relativenumber      " relative line numbers (hybrid with 'number') for motion counts
set ruler               " show the current row and column

set hlsearch            " highlight searches
set incsearch           " incremental searching
set showmatch           " jump to matches when entering regexp
set ignorecase          " ignore case when searching
set smartcase           " no ignorecase if uppercase char present

set belloff=all         " turn off all bells (Neovim replacement for visualbell/t_vb)

set backspace=indent,eol,start  " make backspace behave

syntax on               " syntax highlighting
filetype on             " detect file type
filetype indent on      " load indent file for the file type
