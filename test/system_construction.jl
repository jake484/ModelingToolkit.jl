using ModelingToolkit
using Test

# Define some variables
@parameters t() σ() ρ() β()
@variables x(t) y(t) z(t)
@derivatives D'~t

function _clean(O::Operation)
    @assert isa(O.op, Variable)
    return O.op
end
_clean(x::Variable) = x
function test_diffeq_inference(name, sys, iv, dvs, ps)
    @testset "ODESystem construction: $name" begin
        @test independent_variables(sys) == Set([_clean(iv)])
        @test dependent_variables(sys)   == Set(_clean.(dvs))
        @test parameters(sys)            == Set(_clean.(ps))
    end
end
function test_nlsys_inference(name, sys, vs, ps)
    @testset "NonlinearSystem construction: $name" begin
        @test dependent_variables(sys) == Set(vs)
        @test parameters(sys)          == Set(_clean.(ps))
    end
end

# Define a differential equation
eqs = [D(x) ~ σ*(y-x),
       D(y) ~ x*(ρ-z)-y,
       D(z) ~ x*y - β*z]
de = ODESystem(eqs)
test_diffeq_inference("standard", de, t, (x, y, z), (σ, ρ, β))
generate_function(de, [x,y,z], [σ,ρ,β])
generate_function(de, [x,y,z], [σ,ρ,β]; version=ModelingToolkit.SArrayFunction)
jac_expr = generate_jacobian(de)
jac = calculate_jacobian(de)
f = ODEFunction(de, [x,y,z], [σ,ρ,β])
ModelingToolkit.generate_ode_iW(de)

@testset "time-varying parameters" begin
    @parameters σ′(t-1)
    eqs = [D(x) ~ σ′*(y-x),
           D(y) ~ x*(ρ-z)-y,
           D(z) ~ x*y - β*z]
    de = ODESystem(eqs)
    test_diffeq_inference("global iv-varying", de, t, (x, y, z), (σ′, ρ, β))
    @test begin
        f = eval(generate_function(de, [x,y,z], [σ′,ρ,β]))
        du = [0.0,0.0,0.0]
        f(du, [1.0,2.0,3.0], [x->x+7,2,3], 5.0)
        du ≈ [11, -3, -7]
    end

    @parameters σ
    eqs = [D(x) ~ σ(t-1)*(y-x),
           D(y) ~ x*(ρ-z)-y,
           D(z) ~ x*y - β*z]
    de = ODESystem(eqs)
    test_diffeq_inference("single internal iv-varying", de, t, (x, y, z), (σ, ρ, β))
    @test begin
        f = eval(generate_function(de, [x,y,z], [σ,ρ,β]))
        du = [0.0,0.0,0.0]
        f(du, [1.0,2.0,3.0], [x->x+7,2,3], 5.0)
        du ≈ [11, -3, -7]
    end

    eqs = [D(x) ~ x + 10σ(t-1) + 100σ(t-2) + 1000σ(t^2)]
    de = ODESystem(eqs)
    test_diffeq_inference("many internal iv-varying", de, t, (x,), (σ,))
    @test begin
        f = eval(generate_function(de, [x], [σ]))
        du = [0.0]
        f(du, [1.0], [t -> t + 2], 5.0)
        du ≈ [27561]
    end
end

# Conversion to first-order ODEs #17
@derivatives D3'''~t
@derivatives D2''~t
@variables u(t) u_tt(t) u_t(t) x_t(t)
eqs = [D3(u) ~ 2(D2(u)) + D(u) + D(x) + 1
       D2(x) ~ D(x) + 2]
de = ODESystem(eqs)
de1 = ode_order_lowering(de)
lowered_eqs = [D(u_tt) ~ 2u_tt + u_t + x_t + 1
               D(x_t)  ~ x_t + 2
               D(u_t)  ~ u_tt
               D(u)    ~ u_t
               D(x)    ~ x_t]
@test de1 == ODESystem(lowered_eqs)

# Internal calculations
a = y - x
eqs = [D(x) ~ σ*a,
       D(y) ~ x*(ρ-z)-y,
       D(z) ~ x*y - β*z]
de = ODESystem(eqs)
generate_function(de, [x,y,z], [σ,ρ,β])
jac = calculate_jacobian(de)
f = ODEFunction(de, [x,y,z], [σ,ρ,β])

# Define a nonlinear system
eqs = [0 ~ σ*(y-x),
       0 ~ x*(ρ-z)-y,
       0 ~ x*y - β*z]
ns = NonlinearSystem(eqs, [x,y,z])
test_nlsys_inference("standard", ns, (x, y, z), (σ, ρ, β))

generate_function(ns, [x,y,z], [σ,ρ,β])

@derivatives D'~t
@parameters A() B() C()
_x = y / C
eqs = [D(x) ~ -A*x,
       D(y) ~ A*x - B*_x]
de = ODESystem(eqs)
@test begin
    f = eval(generate_function(de, [x,y], [A,B,C]))
    du = [0.0,0.0]
    f(du, [1.0,2.0], [1,2,3], 0.0)
    du ≈ [-1, -1/3]
end

# Now nonlinear system with only variables
@variables x() y() z()
@parameters σ() ρ() β()

# Define a nonlinear system
eqs = [0 ~ σ*(y-x),
       0 ~ x*(ρ-z)-y,
       0 ~ x*y - β*z]
ns = NonlinearSystem(eqs, [x,y,z])
jac = calculate_jacobian(ns)
@testset "nlsys jacobian" begin
    @test isequal(jac[1,1], σ * -1)
    @test isequal(jac[1,2], σ)
    @test isequal(jac[1,3], 0)
    @test isequal(jac[2,1], ρ - z)
    @test isequal(jac[2,2], -1)
    @test isequal(jac[2,3], x * -1)
    @test isequal(jac[3,1], y)
    @test isequal(jac[3,2], x)
    @test isequal(jac[3,3], -1 * β)
end
nlsys_func = generate_function(ns, [x,y,z], [σ,ρ,β])
jac_func = generate_jacobian(ns)
f = @eval eval(nlsys_func)

# Intermediate calculations
# Define a nonlinear system
eqs = [0 ~ σ*a,
       0 ~ x*(ρ-z)-y,
       0 ~ x*y - β*z]
ns = NonlinearSystem(eqs, [x,y,z])
nlsys_func = generate_function(ns, [x,y,z], [σ,ρ,β])
jac = calculate_jacobian(ns)
jac = generate_jacobian(ns)
