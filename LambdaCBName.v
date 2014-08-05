(* Calculation of a compiler for the lambda calculus + arithmetic. *)
Require Import List.
Require Import ListIndex.
Require Import Tactics.

Inductive Expr : Set := 
| Val : nat -> Expr 
| Add : Expr -> Expr -> Expr
| Var : nat -> Expr
| Abs : Expr -> Expr
| App : Expr -> Expr -> Expr.

Inductive Thunk : Set  :=
  | thunk : Expr -> list Thunk -> Thunk.

Definition Env : Set := list Thunk.

Inductive Value : Set :=
| Num : nat -> Value
| Clo : Expr -> Env -> Value.

Reserved Notation "x ⇓[ e ] y" (at level 80, no associativity).

Inductive eval : Expr -> Env -> Value -> Prop :=
| eval_val e n : Val n ⇓[e] Num n
| eval_add e x y m n : x ⇓[e] Num m -> y ⇓[e] Num n -> Add x y ⇓[e] Num (m + n)
| eval_var e e' x i v : nth e i = Some (thunk x e') -> x ⇓[e'] v -> Var i ⇓[e] v
| eval_abs e x : Abs x ⇓[e] Clo x e
| eval_app e e' x x' x'' y  : x ⇓[e] Clo x' e' -> x' ⇓[thunk y e :: e'] x'' -> App x y ⇓[e] x''
where "x ⇓[ e ] y" := (eval x e y).

Inductive Code : Set :=
| PUSH : nat -> Code -> Code
| ADD : Code -> Code
| RET : Code
| LOOKUP : nat -> Code -> Code
| APP : Code -> Code -> Code
| ABS : Code -> Code -> Code
| HALT : Code.

Fixpoint comp' (e : Expr) (c : Code) : Code :=
  match e with
    | Val n => PUSH n c
    | Add x y => comp' x (comp' y (ADD c))
    | Var i => LOOKUP i c
    | App x y => comp' x (APP (comp' y RET) c)
    | Abs x => ABS (comp' x RET) c

  end.

Definition comp (e : Expr) : Code := comp' e HALT.

Inductive Thunk' : Set  :=
  | thunk' : Code -> list Thunk' -> Thunk'.

Definition Env' : Set := list Thunk'.

Inductive Value' : Set :=
| Num' : nat -> Value'
| Clo' : Code -> Env' -> Value'.


Inductive Elem : Set :=
| VAL : Value' -> Elem 
| CLO : Code -> Env' -> Elem
.
Definition Stack : Set := list Elem.

Inductive Conf : Set := 
| conf : Code -> Stack -> Env' -> Conf.

Notation "⟨ x , y , e ⟩" := (conf x y e).

Reserved Notation "x ==> y" (at level 80, no associativity).
Inductive VM : Conf -> Conf -> Prop :=
| vm_push n c s e :  ⟨PUSH n c, s, e⟩ ==> ⟨c, VAL (Num' n) :: s, e⟩
| vm_add c m n s e : ⟨ADD c, VAL (Num' n) :: VAL (Num' m) :: s, e⟩
                       ==> ⟨c, VAL (Num'(m + n)) :: s, e⟩
| vm_ret v c e e' s  : ⟨RET, VAL v :: CLO c e :: s, e'⟩ ==> ⟨c, VAL v :: s, e⟩
| vm_lookup e e' i c c' s : nth e i = Some (thunk' c' e') -> ⟨LOOKUP i c, s, e ⟩ ==> ⟨c', CLO c e :: s, e' ⟩
| vm_app c c' c'' e e' s : ⟨APP c' c, VAL (Clo' c'' e') :: s, e⟩
                           ==> ⟨c'', CLO c e :: s, thunk' c' e :: e'⟩
| vm_abs c c' s e : ⟨ABS c' c, s, e ⟩ ==> ⟨c, VAL (Clo' c' e) :: s, e ⟩
where "x ==> y" := (VM x y).



Fixpoint convT (t : Thunk) : Thunk' :=
  match t with
    | thunk x e => thunk' (comp' x RET) (map convT e)
  end.

Definition convE : Env -> Env' := map convT.

Fixpoint convV (v : Value) : Value' :=
  match v with
    | Num n => Num' n
    | Clo x e => Clo' (comp' x RET) (convE e)
  end.


(* Boilerplate to import calculation tactics *)
Module VM <: Preorder.
Definition Conf := Conf.
Definition VM := VM.
End VM.
Module VMCalc := Calculation VM.
Import VMCalc.


Theorem spec p e r c s : p ⇓[e] r -> ⟨comp' p c, s, convE e⟩ 
                                 =>> ⟨c , VAL (convV r) :: s, convE e⟩.
Proof.
  intros.
  generalize dependent c.
  generalize dependent s.
  induction H;intros.


  begin
  ⟨c, VAL (Num' n) :: s, convE e⟩.
  <== { apply vm_push }
  ⟨PUSH n c, s, convE e⟩.
  [].

  begin
    ⟨c, VAL (Num' (m + n)) :: s, convE e ⟩.
  <== { apply vm_add }
    ⟨ADD c, VAL (Num' n) :: VAL (Num' m) :: s, convE e⟩. 
  <<= { apply IHeval2 }
  ⟨comp' y (ADD c), VAL (Num' m) :: s, convE e⟩.
  <<= { apply IHeval1 }
  ⟨comp' x (comp' y (ADD c)), s, convE e⟩.
  [].


  begin
    ⟨c, VAL (convV v) :: s, convE e ⟩.
  <== {apply vm_ret}
    ⟨RET, VAL (convV v) :: CLO c (convE e) :: s, convE e'⟩.
  <<= {apply IHeval}
    ⟨comp' x RET, CLO c (convE e) :: s, convE e'⟩.
  <== {apply vm_lookup; unfold convE; erewrite nth_map; eauto;reflexivity}
    ⟨LOOKUP i c, s, convE e ⟩.
  [].

  begin
    ⟨c, VAL (Clo' (comp' x RET) (convE e)) :: s, convE e ⟩.
  <== { apply vm_abs }
    ⟨ABS (comp' x RET) c, s, convE e ⟩.
  [].
  
  begin
    ⟨c, VAL (convV x'') :: s, convE e ⟩.
  <== { apply vm_ret }
    ⟨RET, VAL (convV x'') :: CLO c (convE e) :: s, convE (thunk y e :: e') ⟩.
  <<= { apply IHeval2 }
    ⟨comp' x' RET, CLO c (convE e) :: s, convE (thunk y e :: e') ⟩.
  = {reflexivity}
    ⟨comp' x' RET, CLO c (convE e) :: s, thunk' (comp' y RET) (convE e) :: convE e' ⟩.
  <== { apply vm_app }
    ⟨APP (comp' y RET) c, VAL (Clo' (comp' x' RET) (convE e')) :: s, convE e ⟩.
  = { reflexivity }
    ⟨APP (comp' y RET) c, VAL (convV (Clo x' e')) :: s, convE e ⟩.
  <<= { apply IHeval1 }
    ⟨comp' x (APP (comp' y RET) c), s, convE e ⟩.
  [].
Qed.
    

Lemma determ_vm : determ VM.
  intros C C1 C2 V. induction V; intro V'; inversion V'; subst; try reflexivity.
  rewrite H in H5. inversion H5. reflexivity.
Qed.
  

Definition terminates (p : Expr) : Prop := exists r, p ⇓[nil] r.

Theorem sound p s C : terminates p -> ⟨comp p, s, nil⟩ =>>! C -> 
                          exists r, C = ⟨HALT , VAL (convV r) :: s, nil⟩ /\ p ⇓[nil] r.
Proof.
  unfold terminates. intros. destruct H as [r T].
  
  pose (spec p nil r HALT s) as H'. exists r. split. pose (determ_trc determ_vm) as D.
  unfold determ in D. eapply D. eassumption. split. auto. intro. destruct H. 
  inversion H. assumption.
Qed.

  