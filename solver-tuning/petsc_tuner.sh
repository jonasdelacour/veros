
{
ksp_type="-ksp_type";
pc_type="-pc_type";
ksp_types=("bcgs" "cg" "gmres");
pc_types=("pfmg" "gamg");
pc_gamg_type="-pc_gamg_type";
gamg_types=("agg" "geo");
setup="--size 100 100 100 --timesteps 5 --device gpu -ls petsc";
}
for i in ${ksp_types[@]};
do
for j in ${gamg_types[@]};
do
echo python ~/veros/benchmarks/streamfunction_solver_benchmark.py ${setup} --petsc-options ${ksp_type}\ ${i}\ ${pc_gamg_type}\ ${j}
python ~/veros/benchmarks/streamfunction_solver_benchmark.py ${setup} --petsc-options ${ksp_type}\ ${i}\ ${pc_gamg_type}\ ${j}
done
done