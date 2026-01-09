#!/bin/bash


sha512sum_gen() {
    local -r hash_src="$1"

    sha512sum "$hash_src" > "$hash_src.sha512"
}

sha512sum_check() {
    sha512sum --check \
        --strict \
        --warn \
        "$1"
}
