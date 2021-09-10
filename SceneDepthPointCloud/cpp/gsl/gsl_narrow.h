///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2015 Microsoft Corporation. All rights reserved.
//
// This code is licensed under the MIT License (MIT).
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
///////////////////////////////////////////////////////////////////////////////

#ifndef GSL_NARROW_H
#define GSL_NARROW_H
#include "gsl_assert.h" // for Expects
#include "gsl_util.h"   // for narrow_cast
namespace gsl
{
struct narrowing_error : public std::exception
{
    const char* what() const noexcept override { return "narrowing_error"; }
};

// narrow() : a checked version of narrow_cast() that throws if the cast changed the value
template <class T, class U, typename std::enable_if<std::is_arithmetic<T>::value>::type* = nullptr>
// clang-format off
GSL_SUPPRESS(type.1) // NO-FORMAT: attribute
GSL_SUPPRESS(f.6) // NO-FORMAT: attribute // TODO: MSVC /analyze does not recognise noexcept(false)
    // clang-format on
    constexpr T narrow(U u) noexcept(false)
{
    constexpr const bool is_different_signedness =
        (std::is_signed<T>::value != std::is_signed<U>::value);

    const T t = narrow_cast<T>(u);

    if (static_cast<U>(t) != u || (is_different_signedness && ((t < T{}) != (u < U{}))))
    {
        throw narrowing_error{};
    }

    return t;
}

template <class T, class U, typename std::enable_if<!std::is_arithmetic<T>::value>::type* = nullptr>
// clang-format off
GSL_SUPPRESS(type.1) // NO-FORMAT: attribute
GSL_SUPPRESS(f.6) // NO-FORMAT: attribute // TODO: MSVC /analyze does not recognise noexcept(false)
    // clang-format on
    constexpr T narrow(U u) noexcept(false)
{
    const T t = narrow_cast<T>(u);

    if (static_cast<U>(t) != u)
    {
        throw narrowing_error{};
    }

    return t;
}
} // namespace gsl
#endif // GSL_NARROW_H
