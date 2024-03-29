from starkware.cairo.common.bitwise import bitwise_and, bitwise_or, bitwise_xor
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_in_range, assert_le, assert_nn_le, assert_not_zero
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.pow import pow
from starkware.cairo.common.registers import get_ap, get_fp_and_pc
// Import uint384 files (path may change in the future)

from lib.u255 import u255, u512, Uint768, Uint256, Uint384
from lib.curve import P_low, P_high, P_min_1_div_2_low, P_min_1_div_2_high

from starkware.cairo.common.uint256 import uint256_unsigned_div_rem, SHIFT

// Functions for operating elements in a finite field F_p (i.e. modulo a pr ime p), with p of at most 384 bits
namespace f25519 {
    // Computes a + b modulo 2**255-19
    // Assumes a+b < 2^256. If a and b both < PRIME, it is ok.
    func add{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let sum = u255.add(a, b);
        return u255.a_modulo_p_255_19(sum);
    }
    // Computes (a - b) modulo p .
    func sub{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        alloc_locals;

        let b_neg = u255.neg(b);
        let res = u255.add(a, b_neg);
        let le = u255.lt(b, a);

        local Ya_min_Xa: Uint256;

        if (le == 0) {
            let uiu = u255.a_modulo_2_255_19(res);
            assert Ya_min_Xa.low = uiu.low;
            assert Ya_min_Xa.high = uiu.high;
            tempvar range_check_ptr = range_check_ptr;
            //
        } else {
            assert Ya_min_Xa.low = res.low;
            assert Ya_min_Xa.high = res.high - 2 ** 128;
            tempvar range_check_ptr = range_check_ptr;
        }
        // %{ print_u_256_info(ids.Ya_min_Xa, 'Ya_min_xa') %}

        return Ya_min_Xa;
    }

    // Computes a * b modulo p
    func mul{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let full_mul_result: u512 = u255.mul(a, b);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul') %}
        return u512_modulo_p_25519(full_mul_result);
    }

    // Computes 2*a*b modulo p
    func mul2ab{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        let full_mul_result: u512 = u255.mul2ab(a, b);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul2') %}
        return u512_modulo_p_25519(full_mul_result);
    }
    // Computes a*a modulo p
    func square{range_check_ptr}(a: Uint256) -> Uint256 {
        let full_mul_result: u512 = u255.square(a);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul2') %}
        return u512_modulo_p_25519(full_mul_result);
    }
    // Computes 2*a*a modulo p
    func square2{range_check_ptr}(a: Uint256) -> Uint256 {
        let full_mul_result: u512 = u255.square(a);
        let full_mul_result = u255.double_u511(full_mul_result);
        // %{ print_u_512_info(ids.full_mul_result, 'full_mul2') %}
        return u512_modulo_p_25519(full_mul_result);
    }
    func u512_modulo_p_25519{range_check_ptr}(x: u512) -> Uint256 {
        alloc_locals;
        local quotient: u512;
        local remainder: Uint256;
        local div: Uint256 = Uint256(P_low, P_high);
        // To whitelist
        %{
            def split(num: int, num_bits_shift: int, length: int):
                a = []
                for _ in range(length):
                    a.append( num & ((1 << num_bits_shift) - 1) )
                    num = num >> num_bits_shift 
                return tuple(a)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.low, z.high)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))
                
            def pack_extended(z, num_bits_shift: int) -> int:
                limbs = (z.d0, z.d1, z.d2, z.d3)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            x = pack_extended(ids.x, num_bits_shift = 128)
            div = pack(ids.div, num_bits_shift = 128)

            quotient, remainder = divmod(x, div)

            quotient_split = split(quotient, num_bits_shift=128, length=4)

            ids.quotient.d0 = quotient_split[0]
            ids.quotient.d1 = quotient_split[1]
            ids.quotient.d2 = quotient_split[2]
            ids.quotient.d3 = quotient_split[3]

            remainder_split = split(remainder, num_bits_shift=128, length=2)
            ids.remainder.low = remainder_split[0]
            ids.remainder.high = remainder_split[1]
        %}

        let res_mul: Uint768 = u255.mul_u512_by_u256(quotient, div);

        assert res_mul.d4 = 0;
        assert res_mul.d5 = 0;

        let check_val: u512 = u255.add_u512_and_u256(
            u512(res_mul.d0, res_mul.d1, res_mul.d2, res_mul.d3), remainder
        );

        // assert add_carry = 0;
        assert check_val = x;

        let is_valid = u255.lt(remainder, div);
        assert is_valid = 1;

        return remainder;
    }
    func inv_mod_p_uint512{range_check_ptr}(x: u512) -> Uint256 {
        alloc_locals;
        local x_inverse_mod_p: Uint256;
        local p: Uint256 = Uint256(P_low, P_high);
        // To whitelist
        %{
            def pack_512(u, num_bits_shift: int) -> int:
                limbs = (u.d0, u.d1, u.d2, u.d3)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            x = pack_512(ids.x, num_bits_shift = 128)
            p = ids.p.low + (ids.p.high << 128)
            x_inverse_mod_p = pow(x,-1, p) 

            x_inverse_mod_p_split = (x_inverse_mod_p & ((1 << 128) - 1), x_inverse_mod_p >> 128)

            ids.x_inverse_mod_p.low = x_inverse_mod_p_split[0]
            ids.x_inverse_mod_p.high = x_inverse_mod_p_split[1]
        %}

        let x_times_x_inverse: Uint768 = u255.mul_u512_by_u256(
            x, Uint256(x_inverse_mod_p.low, x_inverse_mod_p.high)
        );
        let x_times_x_inverse_mod_p = u255.u768_modulo_p_25519(x_times_x_inverse);
        assert x_times_x_inverse_mod_p = Uint256(1, 0);

        return x_inverse_mod_p;
    }
    // Computes a * b^{-1} modulo p
    // NOTE: The modular inverse of b modulo p is computed in a hint and verified outside the hind with a multiplicaiton
    func div{range_check_ptr}(a: Uint256, b: Uint256) -> Uint256 {
        alloc_locals;
        local p: Uint256 = Uint256(P_low, P_high);
        local b_inverse_mod_p: Uint256;
        // To whitelist
        %{
            from starkware.python.math_utils import div_mod

            def split(a: int):
                return (a & ((1 << 128) - 1), a >> 128)

            def pack(z, num_bits_shift: int) -> int:
                limbs = (z.low, z.high)
                return sum(limb << (num_bits_shift * i) for i, limb in enumerate(limbs))

            a = pack(ids.a, 128)
            b = pack(ids.b, 128)
            p = pack(ids.p, 128)
            # For python3.8 and above the modular inverse can be computed as follows:
            # b_inverse_mod_p = pow(b, -1, p)
            # Instead we use the python3.7-friendly function div_mod from starkware.python.math_utils
            b_inverse_mod_p = div_mod(1, b, p)

            b_inverse_mod_p_split = split(b_inverse_mod_p)

            ids.b_inverse_mod_p.low = b_inverse_mod_p_split[0]
            ids.b_inverse_mod_p.high = b_inverse_mod_p_split[1]
        %}
        let b_times_b_inverse = mul(b, b_inverse_mod_p);
        assert b_times_b_inverse = Uint256(1, 0);

        let res: Uint256 = mul(a, b_inverse_mod_p);
        return res;
    }

    // Computes (a**exp) % p. Using the exponentiation by squaring algorithm, so it takes at most 384 squarings: https://en.wikipedia.org/wiki/Exponentiation_by_squaring
    func pow{range_check_ptr}(a: Uint256, exp: Uint256) -> Uint256 {
        alloc_locals;
        let is_exp_zero = u255.eq(exp, Uint256(0, 0));

        if (is_exp_zero == 1) {
            let o = Uint256(1, 0);
            return o;
        }

        let is_exp_one = u255.eq(exp, Uint256(1, 0));
        if (is_exp_one == 1) {
            // If exp = 1, it is possible that `a` is not reduced mod p,
            // so we check and reduce if necessary
            let is_a_lt_p = u255.lt(a, Uint256(P_low, P_high));
            if (is_a_lt_p == 1) {
                return a;
            } else {
                let remainder = u255.a_modulo_p_255_19(a);
                return remainder;
            }
        }

        let (exp_div_2, remainder) = u255.unsigned_div_rem(exp, Uint256(2, 0));
        let is_remainder_zero = u255.eq(remainder, Uint256(0, 0));

        if (is_remainder_zero == 1) {
            // NOTE: Code is repeated in the if-else to avoid declaring a_squared as a local variable
            let a_squared_mod_f25519: Uint256 = square(a);
            let res = pow(a_squared_mod_f25519, exp_div_2);
            return res;
        } else {
            let a_squared_mod_f25519: Uint256 = square(a);
            let res = pow(a_squared_mod_f25519, exp_div_2);
            let res_mul = mul(a, res);
            return res_mul;
        }
    }
    // Finds a square of x in F_p, i.e. x ≅ y**2 (mod p) for some y
    // To do so, the following is done in a hint:
    // 0. Assume x is not  0 mod p
    // 1. Check if x is a square, if yes, find a square root r of it
    // 2. If (and only if not), then gx *is* a square (for g a generator of F_p^*), so find a square root r of it
    // 3. Check in Cairo that r**2 = x (mod p) or r**2 = gx (mod p), respectively
    // NOTE: The function assumes that 0 <= x < p
    func get_square_root{range_check_ptr}(x: Uint256) -> (success: felt, res: Uint256) {
        alloc_locals;

        // TODO: Create an equality function within field_arithmetic to avoid overflow bugs
        let is_zero = u255.eq(x, Uint256(0, 0));
        if (is_zero == 1) {
            return (1, Uint256(0, 0));
        }
        // let x = Uint384(x.low, x.high, 0);
        local p: Uint256 = Uint256(P_low, P_high);

        local generator: Uint256 = Uint256(P_min_1_div_2_low, P_min_1_div_2_high);
        local success_x: felt;
        local success_gx: felt;
        local sqrt_x: Uint256;
        local sqrt_gx: Uint256;

        // Compute square roots in a hint
        // To whitelist
        %{
            from starkware.python.math_utils import is_quad_residue, sqrt

            def split(a: int):
                return (a & ((1 << 128) - 1), a >> 128)

            def pack(z) -> int:
                return z.low + (z.high << 128)

            generator = pack(ids.generator)
            x = pack(ids.x)
            p = pack(ids.p)

            success_x = is_quad_residue(x, p)
            root_x = sqrt(x, p) if success_x else None
            success_gx = is_quad_residue(generator*x, p)
            root_gx = sqrt(generator*x, p) if success_gx else None

            # Check that one is 0 and the other is 1
            if x != 0:
                assert success_x + success_gx == 1

            # `None` means that no root was found, but we need to transform these into a felt no matter what
            if root_x == None:
                root_x = 0
            if root_gx == None:
                root_gx = 0
            ids.success_x = int(success_x)
            ids.success_gx = int(success_gx)
            split_root_x = split(root_x)
            print('split root x', split_root_x)
            split_root_gx = split(root_gx)
            ids.sqrt_x.low = split_root_x[0]
            ids.sqrt_x.high = split_root_x[1]
            ids.sqrt_gx.low = split_root_gx[0]
            ids.sqrt_gx.high = split_root_gx[1]
        %}

        // Verify that the values computed in the hint are what they are supposed to be
        %{ print_u_256_info(ids.sqrt_x, 'root') %}
        let gx: Uint256 = mul(generator, x);
        if (success_x == 1) {
            let sqrt_x_squared: Uint256 = mul(sqrt_x, sqrt_x);

            // Note these checks may fail if the input x does not satisfy 0<= x < p
            // TODO: Create a equality function within field_arithmetic to avoid overflow bugs
            let check_x = u255.eq(x, sqrt_x_squared);
            assert check_x = 1;
        } else {
            // In this case success_gx = 1
            let sqrt_gx_squared: Uint256 = mul(sqrt_gx, sqrt_gx);
            let check_gx = u255.eq(gx, sqrt_gx_squared);
            assert check_gx = 1;
        }

        // Return the appropriate values
        if (success_x == 0) {
            // No square roots were found
            // Note that Uint256(0, 0) is not a square root here, but something needs to be returned
            return (0, Uint256(0, 0));
        } else {
            return (1, sqrt_x);
        }
    }

    // TODO: not tested
    // RIght now thid function expects a and be to be between 0 and p-1
    func eq{range_check_ptr}(a: Uint256, b: Uint256) -> (res: felt) {
        let (is_a_eq_b) = u255.eq(a, b);
        return (is_a_eq_b,);
    }

    // TODO: not tested
    func is_zero{range_check_ptr}(a: Uint256) -> (bool: felt) {
        let (is_a_zero) = u255.eq(a, Uint256(0, 0));
        if (is_a_zero == 1) {
            return (1,);
        } else {
            return (0,);
        }
    }
    // computes x^((PRIME+3)/8) mod PRIME efficiently
    func pow_prime_3_div_8{range_check_ptr}(x: Uint256) -> Uint256 {
        alloc_locals;
        // let P = Uint256(P_low, P_high);

        let x2 = f25519.square(x);
        let b2 = f25519.mul(x2, x);

        let b4t = f25519.pow(b2, Uint256(2 ** 2, 0));
        let b4 = f25519.mul(b4t, b2);

        let b5t = f25519.pow(b4, Uint256(2, 0));
        let b5 = f25519.mul(b5t, x);

        let b10t = f25519.pow(b5, Uint256(2 ** 5, 0));
        let b10 = f25519.mul(b10t, b5);

        let b20t = f25519.pow(b10, Uint256(2 ** 10, 0));
        let b20 = f25519.mul(b20t, b10);

        let b40t = f25519.pow(b20, Uint256(2 ** 20, 0));
        let b40 = f25519.mul(b40t, b20);

        let b80t = f25519.pow(b40, Uint256(2 ** 40, 0));
        let b80 = f25519.mul(b80t, b40);

        let b160t = f25519.pow(b80, Uint256(2 ** 80, 0));
        let b160 = f25519.mul(b160t, b80);

        let b240t = f25519.pow(b160, Uint256(2 ** 80, 0));
        let b240 = f25519.mul(b240t, b80);
        let b250t = f25519.pow(b240, Uint256(2 ** 10, 0));
        let b250 = f25519.mul(b250t, b10);
        %{ print_u_256_info(ids.b250, "b250") %}
        let pow_p_5_8t = f25519.pow(b250, Uint256(2 ** 2, 0));
        %{ print_u_256_info(ids.pow_p_5_8t, "pow_p_5_8t") %}

        let pow_p_5_8 = f25519.mul(pow_p_5_8t, x2);
        %{ print_u_256_info(ids.pow_p_5_8, "pow_p_5_8") %}

        return pow_p_5_8;
    }
}
