λ contract(x). pre ∩ post ∩ invariant → stated
| violated(pre) ≡ caller_bug | violated(post) ≡ impl_bug | violated(invariant) ≡ design_bug
| post(this) ⊃ pre(next) ∀ callers
